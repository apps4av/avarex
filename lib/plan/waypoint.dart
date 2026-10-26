
import 'package:avaremp/destination/destination.dart';

class Waypoint {

  final Destination _destination;
  List<Destination> destinationsOnRoute = [];
  int currentDestinationIndex = 0;

  /// Cruise altitude for the leg to this waypoint. Null uses the plan altitude.
  int? altitudeFt;

  /// Altitude the navigation log uses for this leg. Null uses [altitudeFt].
  int? navAltitudeFt;

  /// Cruise true airspeed and fuel flow chosen for this leg. Null uses the plan ASpd and GPH.
  double? cruiseKtas;
  double? cruiseGph;

  /// Per-fix cruise altitudes inside an airway or procedure, by route index.
  final Map<int, int> fixAltitudeFt = {};
  final Map<int, double> fixCruiseKtas = {};
  final Map<int, double> fixCruiseGph = {};

  Waypoint(this._destination);

  /// Altitude for this waypoint, or for fix [fixIndex] inside an airway or procedure.
  int effectiveAltitude(int planAltitude, [int? fixIndex]) {
    if (fixIndex != null) {
      final int? fixAltitude = fixAltitudeFt[fixIndex];
      if (fixAltitude != null) {
        return fixAltitude;
      }
    }
    return altitudeFt ?? planAltitude;
  }

  /// Field elevation in feet for an airport, seaplane base, or heliport. Null for anything else.
  static int? airportFieldElevationFt(String type, double? elevation) {
    if (!Destination.isAirport(type) || elevation == null || elevation.isNaN || elevation.isInfinite) {
      return null;
    }
    final int feet = elevation.round();
    if (feet < -2000 || feet > 60000) {
      return null;
    }
    return feet;
  }

  /// Type an altitude by hand. Drops a Best-button cruise speed so the plan ASpd and GPH apply.
  void setAltitudeOnly(int? fixIndex, int value) {
    if (fixIndex == null) {
      altitudeFt = value;
      cruiseKtas = null;
      cruiseGph = null;
    } else {
      fixAltitudeFt[fixIndex] = value;
      fixCruiseKtas.remove(fixIndex);
      fixCruiseGph.remove(fixIndex);
    }
  }

  void clearLegCruise(int? fixIndex) {
    if (fixIndex == null) {
      altitudeFt = null;
      navAltitudeFt = null;
      cruiseKtas = null;
      cruiseGph = null;
    } else {
      fixAltitudeFt.remove(fixIndex);
      fixCruiseKtas.remove(fixIndex);
      fixCruiseGph.remove(fixIndex);
    }
  }

  void setLegCruise(int? fixIndex, {required int altitudeFt, required double ktas, required double gph}) {
    if (fixIndex == null) {
      this.altitudeFt = altitudeFt;
      cruiseKtas = ktas;
      cruiseGph = gph;
    } else {
      fixAltitudeFt[fixIndex] = altitudeFt;
      fixCruiseKtas[fixIndex] = ktas;
      fixCruiseGph[fixIndex] = gph;
    }
  }

  void writeAltitudes(Map<String, Object?> map) {
    Waypoint.writeAltitudeFields(
      map,
      altitudeFt: altitudeFt,
      navAltitudeFt: navAltitudeFt,
      fixAltitudeFt: fixAltitudeFt,
      ktas: cruiseKtas,
      gph: cruiseGph,
      fixKtas: fixCruiseKtas,
      fixGph: fixCruiseGph,
    );
  }

  void readAltitudes(Map<String, dynamic> map) {
    final ({
      int? altitudeFt,
      int? navAltitudeFt,
      Map<int, int> fixAltitudeFt,
      double? ktas,
      double? gph,
      Map<int, double> fixKtas,
      Map<int, double> fixGph,
    }) saved = Waypoint.readAltitudeFields(map);
    altitudeFt = saved.altitudeFt;
    navAltitudeFt = saved.navAltitudeFt;
    cruiseKtas = saved.ktas;
    cruiseGph = saved.gph;
    fixAltitudeFt
      ..clear()
      ..addAll(saved.fixAltitudeFt);
    fixCruiseKtas
      ..clear()
      ..addAll(saved.fixKtas);
    fixCruiseGph
      ..clear()
      ..addAll(saved.fixGph);
  }

  static void writeAltitudeFields(
    Map<String, Object?> map, {
    int? altitudeFt,
    int? navAltitudeFt,
    Map<int, int> fixAltitudeFt = const {},
    double? ktas,
    double? gph,
    Map<int, double> fixKtas = const {},
    Map<int, double> fixGph = const {},
  }) {
    if (altitudeFt != null) {
      map['Alt'] = altitudeFt;
    }
    if (navAltitudeFt != null && navAltitudeFt != altitudeFt) {
      map['NavAlt'] = navAltitudeFt;
    }
    if (ktas != null) {
      map['Tas'] = ktas;
    }
    if (gph != null) {
      map['Gph'] = gph;
    }
    int maxIndex = -1;
    for (final int index in {...fixAltitudeFt.keys, ...fixKtas.keys, ...fixGph.keys}) {
      if (index > maxIndex) {
        maxIndex = index;
      }
    }
    if (maxIndex < 0) {
      return;
    }
    map['FixAlts'] = [for (int index = 0; index <= maxIndex; index++) fixAltitudeFt[index]];
    map['FixTas'] = [for (int index = 0; index <= maxIndex; index++) fixKtas[index]];
    map['FixGph'] = [for (int index = 0; index <= maxIndex; index++) fixGph[index]];
  }

  static ({
    int? altitudeFt,
    int? navAltitudeFt,
    Map<int, int> fixAltitudeFt,
    double? ktas,
    double? gph,
    Map<int, double> fixKtas,
    Map<int, double> fixGph,
  }) readAltitudeFields(Map<String, dynamic> map) {
    int? altitudeFt;
    final Object? alt = map['Alt'];
    if (alt is num && alt >= -2000 && alt <= 60000) {
      altitudeFt = alt.toInt();
    }
    int? navAltitudeFt;
    final Object? nav = map['NavAlt'];
    if (nav is num && nav >= -2000 && nav <= 60000) {
      navAltitudeFt = nav.toInt();
    }
    final Map<int, int> fixAltitudeFt = {};
    _readFixNumbers(map['FixAlts'], (int index, double value) {
      if (value >= 0 && value <= 60000) {
        fixAltitudeFt[index] = value.round();
      }
    });
    return (
      altitudeFt: altitudeFt,
      navAltitudeFt: navAltitudeFt,
      fixAltitudeFt: fixAltitudeFt,
      ktas: _positive(map['Tas']),
      gph: _positive(map['Gph']),
      fixKtas: _readFixMap(map['FixTas']),
      fixGph: _readFixMap(map['FixGph']),
    );
  }

  static double? _positive(Object? value) {
    if (value is num && value > 0) {
      return value.toDouble();
    }
    return null;
  }

  static Map<int, double> _readFixMap(Object? raw) {
    final Map<int, double> values = {};
    _readFixNumbers(raw, (int index, double value) {
      if (value > 0) {
        values[index] = value;
      }
    });
    return values;
  }

  static void _readFixNumbers(Object? raw, void Function(int index, double value) visit) {
    if (raw is! List) {
      return;
    }
    for (int index = 0; index < raw.length; index++) {
      final Object? value = raw[index];
      if (value is num) {
        visit(index, value.toDouble());
      }
    }
  }

  /// Waypoint as entered in the plan. An airway or procedure stays that
  /// airway or procedure, not the fix currently being flown along it.
  Destination get planDestination => _destination;

  Destination get destination {
    return destinationsOnRoute.isNotEmpty ?
    destinationsOnRoute[currentDestinationIndex] : _destination;
  }

  // return points passed, current, next
  List<Destination> getDestinationsNext() {
    if(destinationsOnRoute.isNotEmpty) {
      return currentDestinationIndex == (destinationsOnRoute.length - 1) ?
      [] : destinationsOnRoute.sublist(currentDestinationIndex + 1, destinationsOnRoute.length);
    }
    return [];
  }

  // return points passed, current, next
  List<Destination> getDestinationsPassed() {
    if(destinationsOnRoute.isNotEmpty) {
      return currentDestinationIndex == 0 ?
      [] : destinationsOnRoute.sublist(0, currentDestinationIndex);
    }
    return [];
  }

  // return points passed, current, next
  List<Destination> getDestinationsCurrent() {
    if(destinationsOnRoute.isNotEmpty) {
      return [destinationsOnRoute[currentDestinationIndex]];
    }
    return [];
  }

}
