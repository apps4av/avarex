import 'dart:async';
import 'package:avaremp/instruments/plate_profile_widget.dart';
import 'package:universal_io/io.dart';
import 'dart:math';
import 'package:avaremp/destination/airport.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/place/saa.dart';

import 'db_general.dart';

class MainDatabaseHelper {
  MainDatabaseHelper._();

  static final MainDatabaseHelper _db = MainDatabaseHelper._();

  static MainDatabaseHelper get db => _db;
  static Database? _database;

  static const String _limit = "20"; // limit results

  Future<Database?> get database async {
    if (_database != null) {
      return _database;
    }
    _database = await _initDB();
    return _database;
  }

  Future<Database> _initDB() async {
    Directory documentsDirectory = Directory(Storage().dataDir);
    String path = join(documentsDirectory.path, "main.db");
    return
      await openDatabase(path, onOpen: (db) {});
  }

  Future<List<LatLng>> findObstacles(LatLng point, double altitude) async {
    final db = await database;
    if (db != null) {
      String qry = "select ARPLatitude, ARPLongitude, Height from obs where (Height > ${altitude - 200}) and (ARPLatitude > ${point.latitude - 0.4}) and (ARPLatitude < ${point.latitude + 0.4}) and (ARPLongitude > ${point.longitude - 0.4}) and (ARPLongitude < ${point.longitude + 0.4})";
      List<Map<String, Object?>> maps = await DbGeneral.query(db, qry);
      return List.generate(maps.length, (i) {
        return LatLng(maps[i]['ARPLatitude'] as double, maps[i]['ARPLongitude'] as double);
      });
    }
    return [];

  }

  Future<List<String>> findProcedures(String airportIdentifier) async {
    final db = await database;
    if (db != null) {
      String qry = "select distinct airport_identifier, sid_star_approach_identifier, transition_identifier from cifp_sid_star_app where"
          " trim(airport_identifier) = '$airportIdentifier'";
      return DbGeneral.query(db, qry).then((maps) {
        return List.generate(maps.length, (i) {
          String id = (maps[i]['sid_star_approach_identifier'] as String).trim();
          String transition = (maps[i]['transition_identifier'] as String).trim();
          return "$airportIdentifier.$id${transition.isEmpty ? '' : '.'}$transition"; // transition is optional
        });
      });
    }
    return Future.value([]);
  }

  // Use exact = true for exact match, otherwise for search use exact = false
  Future<List<Destination>> findDestinations(String match, {bool exact = false}) async {
    List<Map<String, dynamic>> maps = [];
    List<Map<String, dynamic>> mapsAirways = [];
    List<Map<String, dynamic>> mapsProcedures = [];
    String? airport;

    RegExp radial = RegExp(r"([A-Za-z0-9]{2,4})([0-9]{6})");
    if(radial.hasMatch(match)) {
      // radial
      RegExpMatch? m = radial.firstMatch(match);
      if(m != null) {
        String matchD = (m.group(1) as String).toUpperCase();
        String radial = m.group(2) as String;
        String angle = radial.substring(0, 3);
        String distance = radial.substring(3);
        final db = await database;
        if (db != null) {
          maps = await DbGeneral.query(db,
                  "      select Type, ARPLongitude, ARPLatitude from airports where LocationID='$matchD' "
                  "union select Type, ARPLongitude, ARPLatitude from nav      where LocationID='$matchD' and (Type != 'VOT')"
                  "union select Type, ARPLongitude, ARPLatitude from fix      where LocationID='$matchD' "
                  "limit 1"
          );
        }
        if(maps.isNotEmpty) {
          LatLng coordinate = LatLng(maps[0]['ARPLatitude'] as double, maps[0]['ARPLongitude'] as double);
          double variation = 0.0;
          (_, variation) = await getGeoInfo(coordinate);
          double angleD = double.parse(angle);
          double distanceD = double.parse(distance);
          LatLng nll = GeoCalculations().calculateOffset(coordinate, distanceD, GeoCalculations.getMagneticHeading(angleD, -variation));
          return [GpsDestination(locationID: Destination.toSexagesimal(nll), type: Destination.typeGps, facilityName: match, coordinate: nll)];
        }
      }
    }
    else if(match.startsWith("!") && match.endsWith("!")) {
      //address between ! and !
      String address = match.substring(1, match.length - 1);
      LatLng? coordinate = await Destination.findGpsCoordinateFromAddressLookup(address);
      if(coordinate != null) {
        return [GpsDestination(locationID: Destination.toSexagesimal(coordinate), type: Destination.typeGps, facilityName: address, coordinate: coordinate)];
      }
    }
    else if(match.contains(",") && match.length == Destination.toSexagesimal(const LatLng(0, 0)).length) {
      // parse sexagesimal coordinate
      LatLng coordinate = Destination.parseFromSexagesimalFullOrPartial(match);
      return [GpsDestination(locationID: Destination.toSexagesimal(coordinate), type: Destination.typeGps, facilityName: "", coordinate: coordinate)];
    }
    final db = await database;
    String eMatch = exact ? " = '$match'" : "like '$match%'";
    if (db != null) {
      maps = await DbGeneral.query(db,
        // combine airports, fix, nav that matches match word and return 3 columns to show in the find result
          "      select LocationID, FacilityName, Type, ARPLongitude, ARPLatitude from airports where ((LocationID $eMatch) or (UPPER(City) = '${match.toUpperCase()}')) "
          "union select LocationID, FacilityName, Type, ARPLongitude, ARPLatitude from nav      where (LocationID $eMatch) "
          "union select LocationID, FacilityName, Type, ARPLongitude, ARPLatitude from fix      where (LocationID $eMatch) "
          "order by Type asc limit $_limit"
      );
      mapsAirways = await DbGeneral.query(db,
          "select name, sequence, Longitude, Latitude from airways where name = '$match' COLLATE NOCASE "
              "order by cast(sequence as integer) asc limit 1"
      );

      // CIFP procedures all separated by .
      List<String> segments = match.split(".");
      if(segments.isNotEmpty) {
        airport = segments[0].toUpperCase();
        String match = "";
        if(segments.length == 2) {
          match = exact ?
            " and trim(sid_star_approach_identifier) =    '${segments[1].toUpperCase()}'  and trim(transition_identifier) = ''" :
            " and trim(sid_star_approach_identifier) like '${segments[1].toUpperCase()}%'";
        }
        else if(segments.length >= 3) {
          match = exact ?
            " and trim(sid_star_approach_identifier) =    '${segments[1].toUpperCase()}'  and trim(transition_identifier) = '${segments[2].toUpperCase()}'" :
            " and trim(sid_star_approach_identifier) like '${segments[1].toUpperCase()}%' and trim(transition_identifier) like '${segments[2].toUpperCase()}%'";
        }
        String qry = "select distinct airport_identifier, sid_star_approach_identifier, transition_identifier from cifp_sid_star_app where"
          " trim(airport_identifier) = '$airport' $match";
        mapsProcedures = await DbGeneral.query(db, qry);
      }
    }

    List<Destination> ret = List.generate(maps.length, (i) {
      return Destination.fromMap(maps[i]);
    });

    if(mapsAirways.isNotEmpty) {
      Destination d = Destination(
          locationID: mapsAirways[0]['name'] as String,
          facilityName: mapsAirways[0]['name'] as String,
          type: Destination.typeAirway,
          coordinate: LatLng(mapsAirways[0]['Latitude'] as double, mapsAirways[0]['Longitude'] as double),
        );
      ret.add(d);
    }

    if(mapsProcedures.isNotEmpty && airport != null) {
      // find the airport for this
      Destination? da = await findAirport(airport);
      if(null != da) {
        // all procedures get airport coordinate, procedures always 3 segments airport.sid.transition
        List<Destination> d = List.generate(mapsProcedures.length, (i) {
          String lid = (mapsProcedures[i]['airport_identifier'] as String).trim();
          String transition = (mapsProcedures[i]['transition_identifier'] as String).trim();
          String id = (mapsProcedures[i]['sid_star_approach_identifier'] as String).trim();
          String name = "$lid.$id${transition.isEmpty ? '' : '.'}$transition"; // transition is optional
          return Destination(locationID: name,
              facilityName: name,
              type: Destination.typeProcedure,
              coordinate: da.coordinate);
        });
        ret.addAll(d);
      }

    }

    return ret;
  }

  Future<Destination> findDestinationByCoordinates(LatLng point, {double factor = 0.001}) async {

    final db = await database;
    if (db != null) {
      num corrFactor = pow(cos(point.latitude * pi / 180.0), 2);
      String asDistance = "((ARPLongitude - ${point
          .longitude}) * (ARPLongitude - ${point.longitude}) * ${corrFactor
          .toDouble()} + (ARPLatitude - ${point
          .latitude}) * (ARPLatitude - ${point.latitude}))";

      String qry =
          "      select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from airports where distance < $factor "
          "union select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from nav      where distance < $factor "
          "union select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from fix      where distance < $factor "
          "order by distance asc limit 1";
      List<Map<String, dynamic>> maps = await DbGeneral.query(db, qry);
      if(maps.isNotEmpty) {
        return Destination.fromMap(maps[0]);
      }
    }
    // always add touch point of GPS, GPS is not a database type so prefix with _
    String gps = Destination.toSexagesimal(point);
    return(Destination(locationID: gps, type: Destination.typeGps, facilityName: Destination.typeGps, coordinate: point));
  }

  Future<List<Destination>> findNear(LatLng point, {double factor = 0.001}) async {
    final db = await database;
    List<Destination> ret = [];
    if (db != null) {
      num corrFactor = pow(cos(point.latitude * pi / 180.0), 2);
      String asDistance = "((ARPLongitude - ${point
          .longitude}) * (ARPLongitude - ${point.longitude}) * ${corrFactor
          .toDouble()} + (ARPLatitude - ${point
          .latitude}) * (ARPLatitude - ${point.latitude}))";

      String qry =
          "      select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from airports where distance < $factor and (Type = 'AIRPORT' or Type = 'SEAPLANE BAS') " // only what shows on chart
          "union select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from nav      where distance < $factor and (Type != 'VOT') "
          "union select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from fix      where distance < $factor "
          "order by Type asc, distance asc limit $_limit";
      List<Map<String, dynamic>> maps = await DbGeneral.query(db, qry);

      ret = List.generate(maps.length, (i) {
        return Destination.fromMap(maps[i]);
      });
    }
    // always add touch point of GPS, GPS is not a database type so prefix with _
    String gps = Destination.toSexagesimal(point);
    ret.add(Destination(locationID: gps, type: Destination.typeGps, facilityName: Destination.typeGps, coordinate: point));
    return(ret);
  }

  Future<List<Saa>> getSaa(LatLng point) async {
    final db = await database;
    List<Saa> ret = [];
    if (db != null) {
      num corrFactor = pow(cos(point.latitude * pi / 180.0), 2);
      String asDistance = "((lon - ${point
          .longitude}) * (lon - ${point.longitude}) * ${corrFactor
          .toDouble()} + (lat - ${point
          .latitude}) * (lat - ${point.latitude}))";

      String qry = "select *, $asDistance as distance from saa where distance < 1 order by distance asc limit $_limit";
      List<Map<String, dynamic>> maps = await DbGeneral.query(db, qry);

      ret = List.generate(maps.length, (i) {
        return Saa.fromMap(maps[i]);
      });
    }
    return(ret);
  }

  Future<String> getFaaName(String icao) async {
    final db = await database;
    if (db != null) {
      String qry = "select FaaID from airports where LocationID = '$icao'";
      List<Map<String, dynamic>> maps = await DbGeneral.query(db, qry);
      if(maps.isNotEmpty) {
        return maps[0]['FaaID'] as String;
      }
    }
    return icao;
  }

  Future<List<Destination>> findNearestAirportsWithRunways(LatLng point, int runwayLength) async {
    final db = await database;
    List<Destination> ret = [];
    if (db != null) {
      num corrFactor = pow(cos(point.latitude * pi / 180.0), 2);
      String asDistance = "((ARPLongitude - ${point
          .longitude}) * (ARPLongitude - ${point.longitude}) * ${corrFactor
          .toDouble()} + (ARPLatitude - ${point
          .latitude}) * (ARPLatitude - ${point.latitude}))";

      String qry =
          "select airports.LocationID, airports.DLID, airports.FacilityName, airports.Type, airports.ARPLongitude, airports.ARPLatitude, airportrunways.Length, $asDistance as distance from airports "
          "left join airportrunways where "
          "airports.DLID = airportrunways.DLID and airports.Type='AIRPORT' and cast (airportrunways.Length as INTEGER) >= $runwayLength "
          "order by distance asc limit $_limit";
      List<Map<String, dynamic>> maps = await DbGeneral.query(db, qry);

      List<String> duplicates = [];
      // get rid of duplicates
      for(Map<String, dynamic> map in maps) {
        if(duplicates.contains(map['LocationID'])) {
          continue;
        }
        ret.add(Destination.fromMap(map));
        duplicates.add(map['LocationID']);
      }

    }
    return(ret);
  }

  Future<List<NavDestination>> findNearestVOR(LatLng point) async {
    final db = await database;
    List<NavDestination> ret = [];
    if (db != null) {
      num corrFactor = pow(cos(point.latitude * pi / 180.0), 2);
      String asDistance = "((ARPLongitude - ${point
          .longitude}) * (ARPLongitude - ${point.longitude}) * ${corrFactor
          .toDouble()} + (ARPLatitude - ${point
          .latitude}) * (ARPLatitude - ${point.latitude}))";

      String qry = "select * from nav where (Type = 'VOR' or Type = 'VORTAC' or Type = 'VOR/DME') order by $asDistance asc limit 4";
      List<Map<String, dynamic>> maps = await DbGeneral.query(db, qry);

      // get rid of duplicates
      for(Map<String, dynamic> map in maps) {
        ret.add(NavDestination.fromMap(map));
      }
    }
    return(ret);
  }

  Future<Destination> findNearNavOrFixElseGps(LatLng point, {double factor = 0.001}) async {
    final db = await database;
    if (db != null) {
      num corrFactor = pow(cos(point.latitude * pi / 180.0), 2);
      String asDistance = "((ARPLongitude - ${point
          .longitude}) * (ARPLongitude - ${point.longitude}) * ${corrFactor
          .toDouble()} + (ARPLatitude - ${point
          .latitude}) * (ARPLatitude - ${point.latitude}))";

      String qry =
          "      select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from nav      where distance < $factor "
          "union select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from fix      where distance < $factor "
          "order by distance asc limit 1";
      List<Map<String, dynamic>> maps = await DbGeneral.query(db, qry);

      return Destination.fromMap(maps[0]);
    }
    // always add touch point of GPS, GPS is not a database type so prefix with _
    String gps = Destination.toSexagesimal(point);
    return Destination(locationID: gps, type: Destination.typeGps, facilityName: Destination.typeGps, coordinate: point);
  }

  Future<AirportDestination?> findAirport(String airport) async {
    List<Map<String, dynamic>> mapsAirports = [];
    List<Map<String, dynamic>> mapsFreq = [];
    List<Map<String, dynamic>> mapsRunways = [];
    List<Map<String, dynamic>> mapsAwos = [];
    final db = await database;
    if (db != null) {
      mapsAirports = await DbGeneral.query(db, "select * from airports       where LocationID = '$airport'");
      if(mapsAirports.isEmpty) {
        return null;
      }
      String dlid = mapsAirports[0]['DLID'] as String;
      mapsFreq = await DbGeneral.query(db,     "select * from airportfreq    where DLID = '$dlid'");
      mapsRunways = await DbGeneral.query(db,  "select * from airportrunways where DLID = '$dlid'");
      mapsAwos = await DbGeneral.query(db,     "select * from awos           where DLID = '$dlid'");
      return AirportDestination.fromMap(mapsAirports[0], mapsFreq, mapsAwos, mapsRunways);
    }

    return null;
  }

  Future<NavDestination?> findNav(String nav) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await DbGeneral.query(db, "select * from nav where LocationID = '$nav' limit 1");
    }
    if(maps.isEmpty) {
      return null;
    }

    return NavDestination.fromMap(maps[0]);
  }

  Future<FixDestination?> findFix(String fix) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await DbGeneral.query(db, "select * from fix where LocationID = '$fix' limit 1");
    }
    if(maps.isEmpty) {
      return null;
    }

    return FixDestination.fromMap(maps[0]);
  }

  Future<AirwayDestination?> findAirway(String airway) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await DbGeneral.query(db, "select name, sequence, Longitude, Latitude from airways where name = '$airway' COLLATE NOCASE "
          "order by cast(sequence as integer) asc");
    }
    if(maps.isEmpty) {
      return null;
    }

    return AirwayDestination.fromMap(maps[0]["name"], maps);
  }

  // procedure is same as airway as its a bunch of points
  Future<ProcedureDestination?> findProcedure(String procedureName) async {
    List<Map<String, dynamic>> maps = [];
    List<String> segments = procedureName.split(".");
    String? qry;
    String lastId = "";
    if(segments.length < 2) {
      return null;
    }
    if(segments.length < 3) {
      segments.add("");
    }

    // sid/star/transition
    qry = "select * from cifp_sid_star_app where trim(airport_identifier) = '${segments[0].toUpperCase()}'"
        " and trim(sid_star_approach_identifier) = '${segments[1].toUpperCase()}'"
        " and trim(transition_identifier) = '${segments[2].toUpperCase()}'"
        " order by trim(sequence_number) asc";
    final db = await database;
    if (db != null) {
      maps = await DbGeneral.query(db, qry);
    }
    if(maps.isEmpty) {
      return null;
    }

    // resolve everything and add to the list
    List<Map<String, dynamic>> mapsCombined = [];
    for(var m in maps) {
      String id = m['fix_identifier'].trim();
      if(id == lastId) {
        // duplicates, need to remove
        continue;
      }
      Destination? d;
      d = await findFix(id);
      if(null == d) {
        d = await findNav(id);
        if(null == d) {
          // runway
          // find runway if not a fix or a nav
          AirportDestination? da = await findAirport(segments[0]);
          if(da != null) {
            LatLng? ll = await Airport.findCoordinatesFromRunway(da, id);
            if(ll != null) {
              d = GpsDestination(locationID: id, type: Destination.typeGps, facilityName: id, coordinate: ll);
            }
          }
        }
      }
      if(null == d) {
        continue;
      }
      Map<String, dynamic> m2 = Map.from(m);
      // name is required so is lat/lon
      m2["Latitude"] = d.coordinate.latitude;
      m2["Longitude"] = d.coordinate.longitude;
      mapsCombined.add(m2);
      lastId = id;
    }
    return ProcedureDestination.fromMap(procedureName, mapsCombined);
  }

  Future<(double, double)> getGeoInfo(LatLng ll) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await DbGeneral.query(db, "select * from geo where Longitude = '${ll.longitude.round()}' and Latitude = '${ll.latitude.round()}' limit 1");
    }
    if(maps.isEmpty) {
      return (0.0, 0.0);
    }

    return (maps[0]['height'] as double, maps[0]['declination'] as double);

  }

  Future<List<ProcedureProfilePoint>> findProcedureProfile(String procedureName) async {

    String? readCifpValue(Map<String, dynamic> map, List<String> keys) {
      for (final key in keys) {
        if (!map.containsKey(key)) {
          continue;
        }
        final value = map[key];
        if (value == null) {
          continue;
        }
        final String text = value.toString().trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
      return null;
    }

    double? parseAltitudeValue(String? raw) {
      if (raw == null) {
        return null;
      }
      final String trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final bool isFlightLevel = trimmed.toUpperCase().contains("FL");
      final String digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) {
        return null;
      }
      final double? value = double.tryParse(digits);
      if (value == null) {
        return null;
      }
      return isFlightLevel ? value * 100 : value;
    }

    double? parseCifpAltitudeFt(Map<String, dynamic> map) {
      final String? altitude1 = readCifpValue(map, [
        'altitude_1',
        'altitude1',
        'altitude',
      ]);
      final String? altitude2 = readCifpValue(map, [
        'altitude_2',
        'altitude2',
      ]);
      final double? alt1 = parseAltitudeValue(altitude1);
      final double? alt2 = parseAltitudeValue(altitude2);
      return alt1 ?? alt2;
    }

    String? readPathAndTermination(Map<String, dynamic> map) {
      return readCifpValue(map, [
        'path_and_termination',
        'path_and_termination_identifier',
        'pathAndTermination',
        'pathAndTerminationIdentifier',
      ]);
    }

    bool isExcludedPathTermination(Map<String, dynamic> map) {
      final String? pathTermination = readPathAndTermination(map);
      if (pathTermination == null) {
        return false;
      }
      const Set<String> excluded = {'CA', 'HM', 'DF'};
      return excluded.contains(pathTermination.trim().toUpperCase());
    }

    List<Map<String, dynamic>> maps = [];
    List<String> segments = procedureName.split(".");
    if (segments.length < 2) {
      return [];
    }
    if (segments.length < 3) {
      segments.add("");
    }

    String qry = "select * from cifp_sid_star_app where trim(airport_identifier) = '${segments[0].toUpperCase()}'"
        " and trim(sid_star_approach_identifier) = '${segments[1].toUpperCase()}'"
        " and trim(transition_identifier) = '${segments[2].toUpperCase()}'"
        " order by trim(sequence_number) asc";
    final db = await database;
    if (db != null) {
      maps = await DbGeneral.query(db, qry);
    }
    if (maps.isEmpty) {
      return [];
    }

    List<ProcedureProfilePoint> points = [];
    String lastId = "";
    for (final m in maps) {
      if (isExcludedPathTermination(m)) {
        continue;
      }
      String id = (m['fix_identifier'] as String).trim();
      if (id.isEmpty || id == lastId) {
        continue;
      }
      Destination? d;
      d = await findFix(id);
      if (d == null) {
        d = await findNav(id);
        if (d == null) {
          AirportDestination? da = await findAirport(segments[0]);
          if (da != null) {
            LatLng? ll = await Airport.findCoordinatesFromRunway(da, id);
            if (ll != null) {
              d = GpsDestination(locationID: id, type: Destination.typeGps, facilityName: id, coordinate: ll);
            }
          }
        }
      }
      if (d == null) {
        continue;
      }
      double? altitudeFt = parseCifpAltitudeFt(m);
      points.add(ProcedureProfilePoint(
        fixIdentifier: id,
        coordinate: d.coordinate,
        altitudeFt: altitudeFt,
      ));
      lastId = id;
    }

    return points;
  }
}


