
import 'dart:convert';

import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/airway.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/plan/passage.dart';
import 'package:avaremp/plan/route_generator.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/plan/best_cruise_altitude.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';

import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/destination/destination_calculations.dart';
import 'package:avaremp/io/gps.dart';

class PlanRoute {

  // all segments
  final List<Waypoint> _waypoints = [];
  List<LatLng> _pointsPassed = [];
  List<LatLng> _pointsCurrent = [];
  List<LatLng> _pointsNext = [];
  List<LatLng> _pointsNextHighResolution = [];
  List<double> _pathPassedAltitudes = [];
  List<double> _pathCurrentAltitudes = [];
  List<double> _pathNextLineAltitudes = [];
  List<double> _pathNextAltitudes = [];
  Waypoint? _current; // current one we are flying to
  String name;
  final change = ValueNotifier<int>(0);
  int _altitude = 3000;

  /// Planned altitude in feet. Notifying keeps the 3D path at the new level.
  int get altitude => _altitude;
  set altitude(int value) {
    if (_altitude == value) {
      return;
    }
    _altitude = value;
    change.value++;
  }
  int fore = 6;
  Passage? _passage;
  List<Destination> _allDestinations = [];
  List<Destination> _nextDestinations = [];

  DestinationCalculations? totalCalculations;

  /// Altitudes chosen along the route, with climb and descent between them.
  CruiseProfile? cruiseProfile;

  ProfileFlight? _flight;

  int get length => _waypoints.length;
  bool get isNotEmpty => _waypoints.isNotEmpty;

  void _procedureAdjust(Waypoint waypoint) {
    waypoint.currentDestinationIndex = 0; // on change to airway, reset it
    waypoint.destinationsOnRoute = [];
    if (waypoint.planDestination is! ProcedureDestination) {
      return;
    }
    List<Destination> points = [];

    ProcedureDestination procedure = waypoint.planDestination as ProcedureDestination;

    // procedure
    for(Destination d in procedure.points) {
      Destination n = Destination(locationID: procedure.locationID,
          type: d.type,
          facilityName: d.facilityName,
          coordinate: d.coordinate);
      n.secondaryName = d.locationID;
      points.add(n);
    }

    if(points.isNotEmpty) {
      waypoint.destinationsOnRoute = points;
    }

  }

  void _airwayAdjust(Waypoint waypoint) {

    waypoint.currentDestinationIndex = 0; // on change to airway, reset it
    waypoint.destinationsOnRoute = [];
    if (waypoint.planDestination is! AirwayDestination) {
      return;
    }
    List<Destination> points = [];

    // adjust airways, nothing to do when airway is not in the middle of points
    int index = _waypoints.indexOf(waypoint);
    AirwayDestination airway = waypoint.planDestination as AirwayDestination;

    if(index > 0 && index < _waypoints.length - 1) {
      // replace the airway with the new airway with the right points
      points = Airway.find(
          _waypoints[index - 1].destination,
          airway,
          _waypoints[index + 1].destination);
    }

    if(points.isNotEmpty) {
      waypoint.destinationsOnRoute = points;
    }
  }

  // expand a list of waypoints with airways and return destinations in them
  // do not use it for current route as some on it may have passed and some may not
  List<Destination> _expand(List<Waypoint> waypoints) {
    List<Destination> destinationsExpanded = [];
    for(int index = 0; index < waypoints.length; index++) {
      Destination destination = waypoints[index].destination;
      // expand airways
      if(Destination.isAirway(destination.type) || Destination.isProcedure(destination.type)) {
        // skip empty airways
        if(waypoints[index].destinationsOnRoute.isEmpty) {
          continue;
        }
        destinationsExpanded.addAll(waypoints[index].destinationsOnRoute);
      }
      else {
        destinationsExpanded.add(destination);
      }
    }
    return destinationsExpanded;
  }

  // connect d0 to d1, modify d1, last destination of d0 goes as first of d1
  void _connect(List<Destination> d0, List<Destination> d1) {
    if (d0.isEmpty) {
      return;
    }
    d1.insert(0, d0[d0.length - 1]);
  }

  List<LatLng> _makePathPoints(List<Destination> path, {bool fine = false}) {
    GeoCalculations calc = GeoCalculations();
    List<LatLng> points = [];
    if(path.length < 2) {
      return [];
    }
    // geo segments
    for(int index = 0; index < path.length - 1; index++) {
      LatLng destination1 = path[index].coordinate;
      LatLng destination2 = path[index + 1].coordinate;
      List<LatLng> routeIntermediate;
      // 1 mile segments if fine points
      routeIntermediate = fine ? calc.findPoints(destination1, destination2, 1) : calc.findPoints(destination1, destination2);
      // Skip first point of subsequent legs to avoid duplicates at waypoint junctions.
      // findPoints includes both endpoints, so consecutive legs would have the shared
      // waypoint appearing twice, causing bearing calculations to return 0 (undefined).
      if(index > 0 && routeIntermediate.isNotEmpty) {
        routeIntermediate = routeIntermediate.sublist(1);
      }
      points.addAll(routeIntermediate);
    }
    return points;
  }

  /// Altitude stored for [destination]: the altitude reached there when a profile
  /// is flying, otherwise the leg that arrives there, or field elevation at an airport endpoint.
  double _storedAltitude(Destination destination) {
    final double? reached = _reachedAltitude(destination);
    if (reached != null) {
      return reached;
    }
    for (final Waypoint waypoint in _waypoints) {
      if (waypoint.destinationsOnRoute.isNotEmpty) {
        final int index = waypoint.destinationsOnRoute.indexOf(destination);
        if (index >= 0) {
          return waypoint.effectiveAltitude(_altitude, index).toDouble();
        }
      } else if (identical(waypoint.planDestination, destination)) {
        return waypoint.effectiveAltitude(_altitude).toDouble();
      }
    }
    return destination.calculations?.altitude ?? _altitude.toDouble();
  }

  int _fixIndex(Destination destination) {
    final int exact = _allDestinations.indexOf(destination);
    if (exact >= 0) {
      return exact;
    }
    return _allDestinations.indexWhere(
      (Destination other) => other.coordinate == destination.coordinate,
    );
  }

  /// Altitude the airplane has reached at [destination] along the flown profile.
  double? _reachedAltitude(Destination destination) {
    final ProfileFlight? flight = _flight;
    if (flight == null) {
      return null;
    }
    final int index = _fixIndex(destination);
    if (index < 0 || index >= flight.fixNm.length) {
      return null;
    }
    return flight.altitudeAt(flight.fixNm[index]);
  }

  /// Altitude shown in the plan Alt field. Still climbing: the altitude reached.
  /// After the cruise step has been reached, that step, including through the
  /// arrival descent.
  double? _reportedAltitude(Destination destination) {
    final ProfileFlight? flight = _flight;
    if (flight == null) {
      return null;
    }
    final int index = _fixIndex(destination);
    if (index < 0 || index >= flight.fixNm.length) {
      return null;
    }
    return flight.reportedAltitudeAt(flight.fixNm[index]);
  }

  Destination? _altitudeDestination(Waypoint waypoint, int? fixIndex) {
    if (fixIndex != null) {
      if (fixIndex < 0 || fixIndex >= waypoint.destinationsOnRoute.length) {
        return null;
      }
      return waypoint.destinationsOnRoute[fixIndex];
    }
    if (waypoint.destinationsOnRoute.isNotEmpty) {
      return null;
    }
    return waypoint.planDestination;
  }

  /// One altitude per point [_makePathPoints] would emit.
  /// Level legs use the navigation-log altitude of the waypoint they arrive at.
  /// [slope] rises from the altitude you leave to the altitude you arrive, so a 3D route
  /// starts at the departure field elevation and ends at the arrival field elevation.
  List<double> _altitudesAlong(List<Destination> path, {bool fine = false, bool slope = false}) {
    final List<double> altitudes = [];
    if (path.length < 2) {
      return altitudes;
    }
    if (_flight != null) {
      final List<double> flown = _profileAltitudes(path, fine: fine);
      if (flown.length == _pointCount(path, fine)) {
        return flown;
      }
    }
    final GeoCalculations calc = GeoCalculations();
    // A flown profile rises only as far as the climb has reached. Painting the
    // cruise target across a one-mile leg draws a climb the airplane cannot fly.
    final bool climbed = _flight != null;
    for (int index = 0; index < path.length - 1; index++) {
      final double storedTo = _storedAltitude(path[index + 1]);
      final double toAltitude = (slope || climbed)
          ? storedTo
          : (path[index + 1].calculations?.altitude ?? storedTo);
      final double fromAltitude = (slope || climbed) ? _storedAltitude(path[index]) : toAltitude;
      List<LatLng> routeIntermediate = fine
          ? calc.findPoints(path[index].coordinate, path[index + 1].coordinate, 1)
          : calc.findPoints(path[index].coordinate, path[index + 1].coordinate);
      final int fullCount = routeIntermediate.length;
      if (index > 0 && routeIntermediate.isNotEmpty) {
        routeIntermediate = routeIntermediate.sublist(1);
      }
      for (int point = 0; point < routeIntermediate.length; point++) {
        if ((!slope && !climbed) || fullCount <= 1) {
          altitudes.add(toAltitude);
          continue;
        }
        final int sample = index > 0 ? point + 1 : point;
        final double t = sample / (fullCount - 1);
        altitudes.add(fromAltitude + (toAltitude - fromAltitude) * t);
      }
    }
    return altitudes;
  }

  int _pointCount(List<Destination> path, bool fine) {
    if (path.length < 2) {
      return 0;
    }
    final GeoCalculations geo = GeoCalculations();
    int count = 0;
    for (int index = 0; index < path.length - 1; index++) {
      List<LatLng> routeIntermediate = fine
          ? geo.findPoints(path[index].coordinate, path[index + 1].coordinate, 1)
          : geo.findPoints(path[index].coordinate, path[index + 1].coordinate);
      if (index > 0 && routeIntermediate.isNotEmpty) {
        routeIntermediate = routeIntermediate.sublist(1);
      }
      count += routeIntermediate.length;
    }
    return count;
  }

  /// Flown altitude at each path point: climb, level, and the arrival descent.
  List<double> _profileAltitudes(List<Destination> path, {required bool fine}) {
    final ProfileFlight? flight = _flight;
    if (flight == null || path.length < 2) {
      return [];
    }
    final int startIndex = _fixIndex(path[0]);
    if (startIndex < 0 || startIndex >= flight.fixNm.length) {
      return [];
    }
    final GeoCalculations geo = GeoCalculations();
    double nm = flight.fixNm[startIndex];
    final List<double> altitudes = [];
    LatLng? previous;
    for (int index = 0; index < path.length - 1; index++) {
      List<LatLng> routeIntermediate = fine
          ? geo.findPoints(path[index].coordinate, path[index + 1].coordinate, 1)
          : geo.findPoints(path[index].coordinate, path[index + 1].coordinate);
      if (index > 0 && routeIntermediate.isNotEmpty) {
        routeIntermediate = routeIntermediate.sublist(1);
      }
      for (final LatLng point in routeIntermediate) {
        if (previous != null) {
          nm += geo.calculateDistance(previous, point);
        }
        previous = point;
        altitudes.add(flight.altitudeAt(nm));
      }
    }
    return altitudes;
  }

  ProfileFlight? _profileFlight() {
    final CruiseProfile? profile = cruiseProfile;
    if (profile == null || _allDestinations.length < 2) {
      return null;
    }
    final RouteTrack track = BestCruiseAltitude.buildTrack([
      for (int index = 0; index < _allDestinations.length - 1; index++)
        (from: _allDestinations[index].coordinate, to: _allDestinations[index + 1].coordinate),
    ], spacingNm: BestCruiseAltitude.terrainSpacingNm);
    if (track.points.length < 2 || (track.totalNm - profile.totalNm).abs() > 2) {
      return null;
    }
    return profile.fly(
      track,
      (LatLng point, int altitude) => WindsCache.getWindsAt(point, altitude.toDouble(), fore),
    );
  }

  void _update(bool changeInPath) {
    if (changeInPath) {
      cruiseProfile = null;
    }
    _flight = null;

    if(_waypoints.isNotEmpty) {
      _current ??= _waypoints[0];
    }

    if(_waypoints.isEmpty) {
      _pointsPassed = [];
      _pointsCurrent = [];
      _pointsNextHighResolution = [];
      _pathPassedAltitudes = [];
      _pathCurrentAltitudes = [];
      _pathNextLineAltitudes = [];
      _pathNextAltitudes = [];
      _pointsNext = [];
      _allDestinations = [];
      _nextDestinations = [];
      totalCalculations = null;
      change.value++;
      return;
    }

    // On change in path, adjust airway
    if(changeInPath) {
      applyEndpointFieldElevations();
      for (int index = 0; index < _waypoints.length; index++) {
        Destination destination = _waypoints[index].destination;
        if (Destination.isAirway(destination.type)) {
          _airwayAdjust(_waypoints[index]); // add all airways
        }
        else if (Destination.isProcedure(destination.type)) {
          _procedureAdjust(_waypoints[index]); // add all airways
        }
      }
    }

    final _DestinationSplit split = _destinationSplit()!;
    _allDestinations = split.all;
    _nextDestinations = split.nextBeforeConnect;
    _flight = _profileFlight();

    // calculate plan
    for(int index = 0; index < _allDestinations.length - 1; index++) {
      _allDestinations[0].calculations = null;
      Destination to = _allDestinations[index + 1];
      DestinationCalculations calc;
      // calculate total from current position to active route
      final ({double tas, double gph, double altitude}) numbers = _legNumbers(to);
      final ProfileFlight? flight = _flight;
      double nm0 = 0;
      double nm1 = 0;
      CruiseStep? step;
      if (flight != null && index + 1 < flight.fixNm.length) {
        nm0 = flight.fixNm[index];
        nm1 = flight.fixNm[index + 1];
        if (split.active == to) {
          nm0 = flight.track.nearest(Gps.toLatLng(Storage().position), nm0, nm1);
        }
        if (nm0 > nm1) {
          nm0 = nm1;
        }
        step = flight.profile.stepAt((nm0 + nm1) / 2);
      }
      final double tas = step != null && step.ktas > 0 ? step.ktas : numbers.tas;
      final double gph = step != null && step.gph > 0 ? step.gph : numbers.gph;
      // The cruise step is the altitude being climbed toward. A one-mile leg
      // is still on that climb, so the log shows the altitude reached at the fix.
      // After the airplane has leveled at that step, the arrival descent leaves
      // the number there.
      double altitude = step?.altitudeFt.toDouble() ?? numbers.altitude;
      if (flight != null && index + 1 < flight.fixNm.length) {
        final bool lastLeg = flight.profile.arriveAtEnd &&
            index + 1 == flight.fixNm.length - 1;
        altitude = flight.reportedAltitudeAt(flight.fixNm[lastLeg ? index : index + 1]);
      }
      if(split.active == to) {
        calc = DestinationCalculations(
          Destination.fromLatLng(Gps.toLatLng(Storage().position)),
          to,
          tas,
          gph,
          altitude);
      }
      else {
        calc = DestinationCalculations(
            _allDestinations[index], to,
            tas,
            gph,
            altitude
        );
      }
      calc.calculateTo();
      if (flight != null && step != null) {
        final ({double timeSeconds, double fuelGal, double distanceNm}) span = flight.span(nm0, nm1);
        calc.time = span.timeSeconds;
        calc.fuel = span.fuelGal;
        calc.distance = span.distanceNm;
        if (span.timeSeconds > 0 && span.distanceNm > 0) {
          calc.groundSpeed = span.distanceNm / (span.timeSeconds / 3600.0);
        }
      }
      to.calculations = calc;
    }

    // calculate passage
    Passage? p = _passage;
    if(null == p && _current != null) {
      p = Passage(_current!.destination.coordinate);
      _passage = p;
    }
    if(null != p) {
      if (p.update(Gps.toLatLng(Storage().position))) {
        // passed
        advance();
        _passage = null;
      }
    }

    // do total calculations
    double speed = 0;
    double distance = 0;
    double time = 0;
    double fuel = 0;
    double total = 0;

    if(split.next.isEmpty) {
      // last leg
      if(_allDestinations.isNotEmpty) {
        totalCalculations = _allDestinations[_allDestinations.length - 1].calculations;
      }
      else {
        totalCalculations = null;
      }
    }
    // sum
    else {
      for (int index = 0; index < split.next.length; index++) {
        if (split.next[index].calculations != null) {
          total++;
          totalCalculations ??= split.next[index].calculations;
          speed += split.next[index].calculations!.groundSpeed;
          distance += split.next[index].calculations!.distance;
          time += split.next[index].calculations!.time;
          fuel += split.next[index].calculations!.fuel;
        }
      }
      if(totalCalculations != null) {
        totalCalculations!.groundSpeed = total == 0 ? speed : speed / total; // div by 0
        totalCalculations!.distance = distance;
        totalCalculations!.time = time;
        totalCalculations!.fuel = fuel;
        totalCalculations!.course = _current != null && _current!.destination.calculations != null ? _current!.destination.calculations!.course : 0;
      }
    }

    // make paths
    _pointsPassed = _makePathPoints(split.passed);
    _pathPassedAltitudes = _altitudesAlong(split.passed, slope: true);
    if (_pathPassedAltitudes.length != _pointsPassed.length) {
      _pathPassedAltitudes = [];
    }
    _pointsNext = _makePathPoints(split.next);
    _pathNextLineAltitudes = _altitudesAlong(split.next, slope: true);
    if (_pathNextLineAltitudes.length != _pointsNext.length) {
      _pathNextLineAltitudes = [];
    }
    _pointsCurrent = _makePathPoints(split.current);
    _pathCurrentAltitudes = _altitudesAlong(split.current, slope: true);
    if (_pathCurrentAltitudes.length != _pointsCurrent.length) {
      _pathCurrentAltitudes = [];
    }
    _pointsNextHighResolution = _makePathPoints(split.next, fine: true);
    _pathNextAltitudes = _altitudesAlong(split.next, fine: true);
    if (_pathNextAltitudes.length != _pointsNextHighResolution.length) {
      _pathNextAltitudes = [];
    }

    change.value++;
  }

  /// Cruise altitude, true airspeed, and fuel flow for the leg that arrives at [to].
  ({double tas, double gph, double altitude}) _legNumbers(Destination to) {
    final double planTas = Storage().settings.getTas();
    final double planGph = Storage().settings.getFuelBurn();
    for (final Waypoint waypoint in _waypoints) {
      if (waypoint.destinationsOnRoute.isNotEmpty) {
        final int index = waypoint.destinationsOnRoute.indexOf(to);
        if (index >= 0) {
          final double? legTas = waypoint.fixCruiseKtas[index];
          final double? legGph = waypoint.fixCruiseGph[index];
          return (
            tas: legTas != null && legTas > 0 ? legTas : planTas,
            gph: legGph != null && legGph > 0 ? legGph : planGph,
            altitude: waypoint.effectiveAltitude(altitude, index).toDouble(),
          );
        }
      } else if (identical(waypoint.planDestination, to)) {
        final double? legTas = waypoint.cruiseKtas;
        final double? legGph = waypoint.cruiseGph;
        final int feet = waypoint.navAltitudeFt ?? waypoint.effectiveAltitude(altitude);
        return (
          tas: legTas != null && legTas > 0 ? legTas : planTas,
          gph: legGph != null && legGph > 0 ? legGph : planGph,
          altitude: feet.toDouble(),
        );
      }
    }
    return (tas: planTas, gph: planGph, altitude: altitude.toDouble());
  }

  /// Departure and arrival airports show field elevation. Returns true when an altitude changes.
  bool applyEndpointFieldElevations() {
    if (_waypoints.isEmpty) {
      return false;
    }
    bool changed = _setAirportFieldElevation(_waypoints.first);
    if (_waypoints.length > 1) {
      changed = _setAirportFieldElevation(_waypoints.last) || changed;
    }
    return changed;
  }

  /// Altitude in the plan Alt field. With a profile, a short leg stays on the
  /// climb. Once the cruise altitude has been reached, Alt stays there while
  /// the path descends to the runway. Field elevation stays stored.
  int rowAltitude(Waypoint waypoint, [int? fixIndex]) {
    final ProfileFlight? flight = _flight;
    if (fixIndex == null && isArrivalAirport(waypoint)) {
      if (flight != null && flight.fixNm.length >= 2) {
        return flight.reportedAltitudeAt(flight.fixNm[flight.fixNm.length - 2]).round();
      }
    } else if (flight != null) {
      final Destination? destination = _altitudeDestination(waypoint, fixIndex);
      if (destination != null) {
        final double? reached = _reportedAltitude(destination);
        if (reached != null) {
          return reached.round();
        }
      }
      return waypoint.effectiveAltitude(_altitude, fixIndex);
    }
    if (fixIndex != null || !isArrivalAirport(waypoint)) {
      return waypoint.effectiveAltitude(_altitude, fixIndex);
    }
    if (waypoint.navAltitudeFt != null) {
      return waypoint.navAltitudeFt!;
    }
    final int? field = Waypoint.airportFieldElevationFt(
      waypoint.planDestination.type,
      waypoint.planDestination.elevation,
    );
    if (waypoint.altitudeFt != null && waypoint.altitudeFt != field) {
      return waypoint.altitudeFt!;
    }
    if (_waypoints.length >= 2) {
      return _waypoints[_waypoints.length - 2].effectiveAltitude(_altitude);
    }
    return waypoint.effectiveAltitude(_altitude);
  }

  /// The leg into the last airport stays at field elevation.
  bool isArrivalAirport(Waypoint waypoint) {
    return _waypoints.length > 1 &&
        identical(waypoint, _waypoints.last) &&
        Waypoint.airportFieldElevationFt(waypoint.planDestination.type, waypoint.planDestination.elevation) != null;
  }

  bool _setAirportFieldElevation(Waypoint waypoint) {
    final int? feet = Waypoint.airportFieldElevationFt(
      waypoint.planDestination.type,
      waypoint.planDestination.elevation,
    );
    if (feet == null) {
      return false;
    }
    if (waypoint.altitudeFt == feet && waypoint.cruiseKtas == null && waypoint.cruiseGph == null) {
      return false;
    }
    waypoint.setAltitudeOnly(null, feet);
    return true;
  }

  /// Type an altitude for one leg. Later cruise altitudes stay where they are.
  void setLegAltitude(Waypoint waypoint, int? fixIndex, int value) {
    final ({double fromNm, double toNm})? span = _legSpan(waypoint, fixIndex);
    final CruiseProfile? profile = cruiseProfile;
    waypoint.setAltitudeOnly(fixIndex, value);
    if (fixIndex == null) {
      waypoint.navAltitudeFt = value;
    }
    if (profile != null && span != null) {
      final CruiseStep previous = profile.stepAt(span.fromNm);
      final double tas = Storage().settings.getTas();
      final double gph = Storage().settings.getFuelBurn();
      cruiseProfile = profile.replaceSpan(
        fromNm: span.fromNm,
        toNm: span.toNm,
        altitudeFt: value,
        ktas: tas > 0 ? tas : previous.ktas,
        gph: gph > 0 ? gph : previous.gph,
      );
    }
    update();
  }

  /// Clear one leg back to the plan altitude. Later cruise altitudes stay where they are.
  void clearLegAltitude(Waypoint waypoint, int? fixIndex) {
    final ({double fromNm, double toNm})? span = _legSpan(waypoint, fixIndex);
    final CruiseProfile? profile = cruiseProfile;
    waypoint.clearLegCruise(fixIndex);
    if (profile != null && span != null) {
      final CruiseStep previous = profile.stepAt(span.fromNm);
      final double tas = Storage().settings.getTas();
      final double gph = Storage().settings.getFuelBurn();
      cruiseProfile = profile.replaceSpan(
        fromNm: span.fromNm,
        toNm: span.toNm,
        altitudeFt: altitude,
        ktas: tas > 0 ? tas : previous.ktas,
        gph: gph > 0 ? gph : previous.gph,
      );
    }
    update();
  }

  /// Distance along the profile for the leg that arrives at [waypoint].
  ({double fromNm, double toNm})? _legSpan(Waypoint waypoint, int? fixIndex) {
    final ProfileFlight? flight = _flight;
    final _DestinationSplit? split = _destinationSplit();
    if (flight == null || split == null) {
      return null;
    }
    for (int index = 0; index < split.all.length - 1; index++) {
      if (index + 1 >= flight.fixNm.length) {
        break;
      }
      final Destination to = split.all[index + 1];
      final bool match = fixIndex != null
          ? waypoint.destinationsOnRoute.indexOf(to) == fixIndex
          : waypoint.destinationsOnRoute.isEmpty && identical(waypoint.planDestination, to);
      if (!match) {
        continue;
      }
      return (fromNm: flight.fixNm[index], toNm: flight.fixNm[index + 1]);
    }
    return null;
  }

  /// Drop per-waypoint altitudes so every leg uses the plan altitude.
  void clearAltitudeOverrides() {
    cruiseProfile = null;
    for (final Waypoint waypoint in _waypoints) {
      waypoint.altitudeFt = null;
      waypoint.navAltitudeFt = null;
      waypoint.cruiseKtas = null;
      waypoint.cruiseGph = null;
      waypoint.fixAltitudeFt.clear();
      waypoint.fixCruiseKtas.clear();
      waypoint.fixCruiseGph.clear();
    }
  }

  /// Included in the saved-plan signature so an altitude edit is written to disk.
  String altitudeSignature() {
    final String legs = _waypoints.map((Waypoint waypoint) {
      final List<int> indexes = {
        ...waypoint.fixAltitudeFt.keys,
        ...waypoint.fixCruiseKtas.keys,
        ...waypoint.fixCruiseGph.keys,
      }.toList()
        ..sort();
      final String fixes = indexes
          .map((int index) =>
              "$index:${waypoint.fixAltitudeFt[index] ?? ""}@${waypoint.fixCruiseKtas[index] ?? ""}/${waypoint.fixCruiseGph[index] ?? ""}")
          .join(",");
      return "${waypoint.altitudeFt ?? ""}:${waypoint.navAltitudeFt ?? ""}@${waypoint.cruiseKtas ?? ""}/${waypoint.cruiseGph ?? ""}[$fixes]";
    }).join(";");
    return "$legs|${cruiseProfile?.signature() ?? ""}";
  }

  /// Every calculated leg, with the waypoint column that shows its altitude.
  /// The active leg starts at the current GPS position, matching the navigation log.
  List<PlanLegTarget> cruiseLegs() {
    final _DestinationSplit? split = _destinationSplit();
    if (split == null) {
      return [];
    }
    final LatLng gps = Gps.toLatLng(Storage().position);
    final List<PlanLegTarget> legs = [];
    for (int index = 0; index < split.all.length - 1; index++) {
      final Destination to = split.all[index + 1];
      final LatLng from = split.active == to ? gps : split.all[index].coordinate;
      final int fromAltitudeFt = _legNumbers(split.all[index]).altitude.round();
      final PlanLegTarget? target = _targetFor(to, from, fromAltitudeFt);
      if (target != null) {
        legs.add(target);
      }
    }
    return legs;
  }

  PlanLegTarget? _targetFor(Destination to, LatLng from, int fromAltitudeFt) {
    for (final Waypoint waypoint in _waypoints) {
      if (waypoint.destinationsOnRoute.isNotEmpty) {
        final int index = waypoint.destinationsOnRoute.indexOf(to);
        if (index >= 0) {
          return PlanLegTarget(
            from: from,
            to: to.coordinate,
            waypoint: waypoint,
            fixIndex: index,
            fromAltitudeFt: fromAltitudeFt,
          );
        }
      } else if (identical(waypoint.planDestination, to)) {
        return PlanLegTarget(
          from: from,
          to: to.coordinate,
          waypoint: waypoint,
          fixIndex: null,
          fromAltitudeFt: fromAltitudeFt,
        );
      }
    }
    return null;
  }

  /// Remaining legs that make up the plan total, in flight order.
  /// The active leg starts at the current GPS position, matching the navigation log.
  List<({LatLng from, LatLng to})> remainingLegs() {
    final _DestinationSplit? split = _destinationSplit();
    if(split == null) {
      return [];
    }
    final Set<Destination> keep = split.next.toSet();
    final LatLng gps = Gps.toLatLng(Storage().position);
    final List<({LatLng from, LatLng to})> legs = [];
    for(int index = 0; index < split.all.length - 1; index++) {
      final Destination to = split.all[index + 1];
      if(!keep.contains(to)) {
        continue;
      }
      final LatLng from = split.active == to ? gps : split.all[index].coordinate;
      legs.add((from: from, to: to.coordinate));
    }
    return legs;
  }

  _DestinationSplit? _destinationSplit() {
    if(_waypoints.isEmpty) {
      return null;
    }
    final int cIndex = _current == null ? 0 : _waypoints.indexOf(_current!);
    final List<Waypoint> waypointsPassed = cIndex == 0 ? [] : _waypoints.sublist(0, cIndex);
    final Waypoint current = _waypoints[cIndex];
    final List<Waypoint> waypointsNext = cIndex == (_waypoints.length - 1) ? [] : _waypoints.sublist(cIndex + 1, _waypoints.length);

    final List<Destination> destinationsPassed = _expand(waypointsPassed);
    final List<Destination> destinationsNext = _expand(waypointsNext);
    final List<Destination> destinationsCurrent = [];
    final Destination destination = current.destination;
    if(Destination.isAirway(destination.type) || Destination.isProcedure(destination.type)) {
      destinationsPassed.addAll(current.getDestinationsPassed());
      destinationsNext.insertAll(0, current.getDestinationsNext());
      destinationsCurrent.addAll(current.getDestinationsCurrent());
    }
    else {
      destinationsCurrent.add(current.destination);
    }

    final List<Destination> all = [];
    all.addAll(destinationsPassed);
    all.addAll(destinationsCurrent);
    all.addAll(destinationsNext);
    final List<Destination> nextBeforeConnect = List<Destination>.from(destinationsNext);

    _connect(destinationsPassed, destinationsCurrent); // current now has last passed
    _connect(destinationsCurrent, destinationsNext); // next has now current

    return _DestinationSplit(
      all: all,
      nextBeforeConnect: nextBeforeConnect,
      passed: destinationsPassed,
      current: destinationsCurrent,
      next: destinationsNext,
      active: current.destination,
    );
  }

  void advance() {
    if(_current != null) {
      if(Destination.isAirway(_current!.destination.type) || Destination.isProcedure(_current!.destination.type)) {
        if(_current!.currentDestinationIndex < _current!.destinationsOnRoute.length - 1) {
          // flying on airway and not done
          _current!.currentDestinationIndex++;
          update();
          return;
        }
      }
      int index = _waypoints.indexOf(_current!);
      index++;
      if (index < _waypoints.length) {
        _setCurrent(_waypoints[index]);
      }
      update();
    }
  }

  void back() {
    if(_current != null) {
      if(Destination.isAirway(_current!.destination.type) || Destination.isProcedure(_current!.destination.type)) {
        if(_current!.currentDestinationIndex > 0) {
          // flying on airway and not first point
          _current!.currentDestinationIndex--;
          update();
          return;
        }
      }
      int index = _waypoints.indexOf(_current!);
      index--;
      if (index > -1) {
        _setCurrent(_waypoints[index]);
      }
      update();
    }
  }

  Destination? getPreviousDestination() {
    if(_current != null) {
      if(Destination.isAirway(_current!.destination.type) || Destination.isProcedure(_current!.destination.type)) {
        if(_current!.currentDestinationIndex > 0) {
          // flying on airway and not first point
          return _current!.destinationsOnRoute[_current!.currentDestinationIndex - 1];
        }
      }
      int index = _waypoints.indexOf(_current!);
      index--;
      if (index > -1) {
        return _waypoints[index].destination;
      }
    }
    return null;
  }

  void update() {
    _update(false);
  }

  Waypoint removeWaypointAt(int index) {
    Waypoint waypoint = _waypoints.removeAt(index);
    _setCurrent((waypoint == _current) ? null : _current); // clear next its removed
    _update(true);
    return(waypoint);
  }

  void addDirectTo(Waypoint waypoint) {
    UserDatabaseHelper.db.addRecent(waypoint.destination);
    addWaypoint(waypoint);
    _setCurrent(_waypoints[_waypoints.indexOf(waypoint)]); // go here
    _update(true);
  }

  void addWaypoint(Waypoint waypoint) {
    UserDatabaseHelper.db.addRecent(waypoint.destination);
    _waypoints.add(waypoint);
    _update(true);
  }

  /// Published altitudes from an approach profile, keyed by fix index on the procedure.
  static Map<int, int> profileAltitudesForFixes(
    List<String> fixIds,
    List<({String fix, double? altitudeFt})> points,
  ) {
    final Map<String, int> byFix = {};
    for (final ({String fix, double? altitudeFt}) point in points) {
      final double? altitude = point.altitudeFt;
      if (altitude == null) {
        continue;
      }
      byFix[point.fix.trim().toUpperCase()] = altitude.round();
    }
    final Map<int, int> matched = {};
    for (int index = 0; index < fixIds.length; index++) {
      final int? altitude = byFix[fixIds[index].trim().toUpperCase()];
      if (altitude != null) {
        matched[index] = altitude;
      }
    }
    return matched;
  }

  /// Set each fix altitude on the plan procedure that matches [procedureName].
  void applyProcedureProfileAltitudes(
    String procedureName,
    List<({String fix, double? altitudeFt})> points,
  ) {
    Waypoint? match;
    for (final Waypoint waypoint in _waypoints.reversed) {
      if (waypoint.planDestination.locationID == procedureName) {
        match = waypoint;
        break;
      }
    }
    if (match == null || match.destinationsOnRoute.isEmpty) {
      return;
    }
    final List<String> fixIds = match.destinationsOnRoute.map((Destination destination) {
      final String name = destination.secondaryName ?? '';
      return name.isNotEmpty ? name : destination.locationID;
    }).toList();
    final Map<int, int> altitudes = profileAltitudesForFixes(fixIds, points);
    if (altitudes.isEmpty) {
      return;
    }
    cruiseProfile = null;
    for (final MapEntry<int, int> entry in altitudes.entries) {
      match.setAltitudeOnly(entry.key, entry.value);
    }
    update();
  }

  void moveWaypoint(int from, int to) {
    Waypoint waypoint = _waypoints.removeAt(from);
    _waypoints.insert(to, waypoint);
    _update(true);
  }

  void setCurrentWaypointWithWaypoint(Waypoint waypoint) {
    _setCurrent(_waypoints[_waypoints.indexOf(waypoint)]);
    update();
  }

  void setCurrentWaypoint(int index) {
    if(_waypoints.isNotEmpty) {
      _setCurrent(_waypoints[index]);
    }
    update();
  }

  // Restore the sub-index within the current waypoint's airway/procedure. Used
  // when reloading a saved plan so we resume on the exact leg we were flying.
  void setCurrentWaypointDestinationIndex(int index) {
    if(_current != null && index >= 0 && index < _current!.destinationsOnRoute.length) {
      _current!.currentDestinationIndex = index;
      update();
    }
  }

  void setCurrentWaypointFromDestinationIndex(int index) {
    if(_allDestinations.length > index) {
      Destination d = _allDestinations[index];
      setCurrentWaypointFromDestination(d);
    }
  }

  Waypoint getWaypointAt(int index) {
    return _waypoints[index];
  }

  List<LatLng> getPathPassed() {
    return _pointsPassed;
  }

  List<double> getPathPassedAltitudes() {
    return _pathPassedAltitudes;
  }

  List<LatLng> getPathCurrent() {
    return _pointsCurrent;
  }

  List<double> getPathCurrentAltitudes() {
    return _pathCurrentAltitudes;
  }

  List<LatLng> getPathNext() {
    return _pointsNext;
  }

  /// Cruise altitude for each point of [getPathNext], level on a leg and stepping at the next fix.
  List<double> getPathNextLineAltitudes() {
    return _pathNextLineAltitudes;
  }

  List<LatLng> getPathNextHighResolution() {
    return _pointsNextHighResolution;
  }

  /// Cruise altitude in feet for each point of [getPathNextHighResolution].
  /// Each leg holds the altitude from the plan, then steps at the next waypoint.
  List<double> getPathNextAltitudes() {
    return _pathNextAltitudes;
  }

  List<Destination> getNextDestinations() {
    return _nextDestinations;
  }

  List<Destination> getAllDestinations() {
    return _allDestinations;
  }

  List<LatLng> getPathFromLocation(Position position) {
    Destination? destination = getCurrentWaypoint()?.destination;
    if(destination == null) {
      return [];
    }
    LatLng destination1 = LatLng(position.latitude, position.longitude);
    LatLng destination2 = destination.coordinate;
    List<LatLng> points = GeoCalculations().findPoints(destination1, destination2);
    return points;
  }

  Waypoint? getCurrentWaypoint() {
    // if no route then destination
    return _current;
  }

  // set waypoint based on destination object
  void setCurrentWaypointFromDestination(Destination d) {
    for(Waypoint w in _waypoints) {
      if(Destination.isAirway(w.destination.type) || Destination.isProcedure(w.destination.type)) {
        int index = w.destinationsOnRoute.indexOf(d);
        if(index >= 0) {
          _setCurrent(w);
          w.currentDestinationIndex = index;
          return;
        }
      }
      else {
        if (w.destination == d) {
          _setCurrent(w);
          return;
        }
      }
    }
  }

  Waypoint? getLastWaypoint() {
    // if no route then destination
    if(_current != null) {
      int index = _waypoints.indexOf(_current!) - 1;
      if(index >= 0) {
        return _waypoints[index];
      }
    }
    return null;
  }

  bool isCurrent(int index) {
    if(_current == null) {
      return false;
    }
    return _waypoints.indexOf(_current!) == index;
  }

  int get currentWaypointIndex {
    if(_current == null) {
      return -1;
    }
    return _waypoints.indexOf(_current!);
  }

  // convert route to json
  String toJson(String name) {
    return jsonEncode(_savedMaps());
  }

  List<Map<String, Object?>> _savedMaps() {
    final List<Map<String, Object?>> maps = _waypoints.map(_savedWaypointMap).toList();
    if (maps.isNotEmpty && cruiseProfile != null) {
      maps.first['_cruiseProfile'] = cruiseProfile!.toJson();
    }
    return maps;
  }

  Map<String, Object?> _savedWaypointMap(Waypoint waypoint) {
    final Map<String, Object?> map = Map<String, Object?>.from(waypoint.destination.toMap());
    waypoint.writeAltitudes(map);
    return map;
  }

  // default constructor creates empty route
  PlanRoute(this.name);

  // clear all waypoints from this plan
  void clear() {
    name = "New Plan";
    _setCurrent(null);
    _waypoints.clear();
    _update(true);
  }

  // copy a plan into this
  void copyFrom(PlanRoute other) {
    name = other.name;
    _setCurrent(null);
    _waypoints.removeRange(0, _waypoints.length);
    for(Waypoint w in other._waypoints) {
      addWaypoint(w);
    }
    cruiseProfile = other.cruiseProfile;
    update();
  }

  // convert json to Route
  static Future<PlanRoute> fromJson(String json, String name, bool reverse) async {
    PlanRoute route = PlanRoute(name);
    List<dynamic> decoded = jsonDecode(json);
    List<Map<String, dynamic>> maps = [];
    for (dynamic entry in decoded) {
      if (entry is Map) {
        maps.add(Map<String, dynamic>.from(entry));
      }
    }
    if(reverse) {
      maps = maps.reversed.toList();
    }
    CruiseProfile? profile;
    for (Map<String, dynamic> map in maps) {
      final Object? raw = map['_cruiseProfile'];
      if (!reverse && raw is Map) {
        profile = CruiseProfile.tryParse(Map<String, dynamic>.from(raw));
      }
      Destination expanded = await DestinationFactory.make(Destination.fromMap(map));
      Waypoint w = Waypoint(expanded);
      w.readAltitudes(map);
      route.addWaypoint(w);
    }
    route.cruiseProfile = profile;
    if (profile != null) {
      route.update();
    }
    return route;
  }

  // Plan received from another AvareX device. Airways and procedures stay the
  // airway or procedure. The active waypoint, and the fix inside it, are set
  // after the route is expanded.
  static Future<PlanRoute> fromLink(String json, String name, int waypointIndex, int destinationIndex) async {
    PlanRoute route = PlanRoute(name.isEmpty ? "New Plan" : name);
    List<dynamic> decoded = jsonDecode(json);
    for (dynamic entry in decoded) {
      if (entry is! Map) {
        continue;
      }
      Map<String, dynamic> map = Map<String, dynamic>.from(entry);
      Object? lat = map["ARPLatitude"];
      Object? lon = map["ARPLongitude"];
      if (lat is num) {
        map["ARPLatitude"] = lat.toDouble();
      }
      if (lon is num) {
        map["ARPLongitude"] = lon.toDouble();
      }
      Destination expanded = await DestinationFactory.make(Destination.fromMap(map));
      Waypoint w = Waypoint(expanded);
      w.readAltitudes(map);
      route.addWaypoint(w);
    }
    if (waypointIndex >= 0 && waypointIndex < route.length) {
      route.setCurrentWaypoint(waypointIndex);
      route.setCurrentWaypointDestinationIndex(destinationIndex);
    }
    return route;
  }

  // convert json to Route
  static Future<PlanRoute> fromLine(String name, String line) async {
    PlanRoute route = PlanRoute(name);
    List<String> split = line.split(" ");

    for (String s in split) {
      if(s.isEmpty) { // skip empty spaces
        continue;
      }
      List<Destination> destinations = await MainDatabaseHelper.db.findDestinations(s, exact: true);
      if(destinations.isEmpty) {
        continue;
      }
      Destination expanded = await DestinationFactory.make(destinations[0]);
      Waypoint w = Waypoint(expanded);
      route.addWaypoint(w);
    }
    return route;
  }

  // Build a route between two airports (enter "DEPART DEST").
  //
  // rfinder.asalink.net is no longer usable (commercial use prohibited), so this
  // uses a built-in offline route generator that routes over the airway network:
  // it joins near the departure, follows airways, and leaves near the destination,
  // emitting the result as a list of waypoints. When [lowAltitudeOnly] is true only
  // Victor and RNAV T airways are used; otherwise the full airway network is used.
  static Future<PlanRoute> fromPreferred(String name, String line, String minAltitude, String maxAltitude, {bool lowAltitudeOnly = false}) async {
    PlanRoute route = PlanRoute(name);
    List<String> split = line.trim().split(RegExp(r"\s+"));

    if(split.length < 2) {
      // source and dest must be present
      return route;
    }

    List<Destination>? destinations = await RouteGenerator(lowAltitudeOnly: lowAltitudeOnly).generate(split[0], split[1]);

    if(destinations == null || destinations.isEmpty) {
      return route;
    }

    // The generator already resolved each waypoint to the exact nav/fix at its
    // coordinate, so build the plan directly. Re-parsing identifiers here would be
    // ambiguous (some fix ids collide with airport city names) and could tear the
    // route apart with huge direct legs to far-away airports.
    for (Destination d in destinations) {
      Destination expanded = await DestinationFactory.make(d);
      route.addWaypoint(Waypoint(expanded));
    }
    return route;
  }

  bool isOnPath(LatLng point) {
    List<LatLng> path = getPathNext() + getPathCurrent() + getPathPassed();
    // given line with equation ax + by + c = 0, distance from point (x0, y0) is abs(ax0 + by0 + c) / sqrt(a^2 + b^2)
    for(int index = 0; index < path.length - 1; index++) {
      LatLng p1 = path[index];
      LatLng p2 = path[index + 1];
      double a = p2.latitude - p1.latitude;
      double b = p1.longitude - p2.longitude;
      double c = p1.latitude * (p2.longitude - p1.longitude) - p1.longitude * (p2.latitude - p1.latitude);
      if(a == 0 && b == 0) {
        continue;
      }
      double dist = ((a * point.longitude + b * point.latitude + c) / sqrt(a * a + b * b)).abs();
      if(dist < 0.01) {
        // on path or close enough
        return true;
      }
    }
    return false;
  }

  @override
  String toString() {
    return _waypoints.map((e) => e.destination.locationID).toList().join(" ");
  }

  double _quickDistance(LatLng ll0, LatLng ll1) {
    // there are equal comparisons on float so round to 5 digits
    return double.parse(((ll0.latitude - ll1.latitude) * (ll0.latitude - ll1.latitude) +
        (ll0.longitude - ll1.longitude) * (ll0.longitude - ll1.longitude)).toStringAsFixed(5));
  }

  // for rubber banding
  void insertWaypoint(Waypoint waypoint) {
    UserDatabaseHelper.db.addRecent(waypoint.destination);

    // in the middle
    if(Storage().planSearch) {
      _waypoints.insert(currentWaypointIndex + 1, waypoint);
      _update(true);
      return;
    }

    if(Destination.isAirway(waypoint.destination.type) || Destination.isProcedure(waypoint.destination.type) || _waypoints.isEmpty) {
      addWaypoint(waypoint); // airways cannot be added in the middle. that's confusing
      return;
    }
    else {
      // take all waypoints then two at a time, create path in between them, then find to which point in the
      // path the new waypoint is closest, then insert it there
      int selected = 0;
      double min = double.infinity;
      LatLng ll = waypoint.destination.coordinate;
      for(int index = 0; index < _waypoints.length - 1; index++) {
        Destination d0 = _waypoints[index].destination;
        Destination d1 = _waypoints[index + 1].destination;
        List<LatLng> path = _makePathPoints([d0, d1], fine: true);
        for(int index0 = 0; index0 < path.length; index0++) {
          double dist = _quickDistance(path[index0], ll);
          if(dist < min) {
            min = dist;
            selected = index;
          }
        }
      }

      Destination d0 = _waypoints[0].destination;
      Destination d1 = _waypoints[_waypoints.length - 1].destination;
      // if closets to first, insert at beginning, if closest to end, at at end, else in the middle
      double dist0 = _quickDistance(d0.coordinate, ll);
      double dist1 = _quickDistance(d1.coordinate, ll);
      if(dist0 <= min) {
        _waypoints.insert(0, waypoint);
      }
      else if(dist1 <= min) {
        _waypoints.add(waypoint);
      }
      else {
        _waypoints.insert(selected + 1, waypoint);
      }
      _setCurrent(_waypoints[0]);
      _update(true);
    }
  }


  // for rubber banding
  void replaceDestination(int index, LatLng ll) {
    if(index >= 0 && index < _allDestinations.length) {
      if(Destination.isAirway(_allDestinations[index].type) || Destination.isProcedure(_allDestinations[index].type)) {
        return;
      }
      for(int d = 0; d < _waypoints.length; d++) {
        if(_waypoints[d].destination == _allDestinations[index]) {
          _waypoints[d] = Waypoint(Destination.fromLatLng(ll));
        }
      }
      _setCurrent(_waypoints[0]);
      _update(true);
    }
  }


  // also for rubber banding
  void replaceDestinationFromDb(int index, LatLng ll) {
    if(index >= 0 && index < _allDestinations.length) {
      if(Destination.isAirway(_allDestinations[index].type) || Destination.isProcedure(_allDestinations[index].type)) {
        return;
      }
      MainDatabaseHelper.db.findNear(ll, factor: 0.0001).then((onValue) { // snap but not too far
        if(Destination.isAirport(onValue[0].type)) {
          MainDatabaseHelper.db.findAirport(onValue[0].locationID).then((airport) {
            for(int d = 0; d < _waypoints.length; d++) {
              if(_waypoints[d].destination == _allDestinations[index]) {
                _waypoints[d] = Waypoint(airport!);
              }
            }
            _setCurrent(_waypoints[0]);
            _update(true);
            return;
          });
        }
        else {
          for(int d = 0; d < _waypoints.length; d++) {
            if(_waypoints[d].destination == _allDestinations[index]) {
              _waypoints[d] = Waypoint(onValue[0]);
              _setCurrent(_waypoints[0]);
              _update(true);
              return;
            }
          }
        }
      });
    }
  }


  void _setCurrent(Waypoint? w) {
    _current = w;
    _passage = null;
  }

  // convert route to json
  Map<String, Object?> toMap(String name) {

    String json = jsonEncode(_savedMaps());

    Map<String, Object?> jsonMap = {'name' : name, 'route' : json};

    return jsonMap;
  }

  // convert json to Route
  static Future<PlanRoute> fromMap(Map<String, Object?> maps, bool reverse) async {
    PlanRoute route = PlanRoute(maps['name'] as String);
    String json = maps['route'] as String;
    List<dynamic> decoded = jsonDecode(json);
    List<Map<String, dynamic>> saved = [];
    for (dynamic entry in decoded) {
      if (entry is Map) {
        saved.add(Map<String, dynamic>.from(entry));
      }
    }
    if(reverse) {
      saved = saved.reversed.toList();
    }
    CruiseProfile? profile;
    for (Map<String, dynamic> map in saved) {
      final Object? raw = map['_cruiseProfile'];
      if (!reverse && raw is Map) {
        profile = CruiseProfile.tryParse(Map<String, dynamic>.from(raw));
      }
      Destination expanded = await DestinationFactory.make(Destination.fromMap(map));
      Waypoint w = Waypoint(expanded);
      w.readAltitudes(map);
      route.addWaypoint(w);
    }
    route.cruiseProfile = profile;
    if (profile != null) {
      route.update();
    }
    return route;
  }

  /// `id|type` of each waypoint as entered, one per line.
  String get linkPointKey {
    return _waypoints.map((Waypoint w) =>
        "${w.planDestination.locationID}|${w.planDestination.type}").join("\n");
  }

  /// JSON array of the plan as entered. Airways and procedures stay the
  /// airway or procedure, not the fix currently being flown.
  String toLinkJson() {
    List<Map<String, Object?>> maps = _waypoints.map((Waypoint w) {
      final Map<String, Object?> map = Map<String, Object?>.from(w.planDestination.toMap());
      w.writeAltitudes(map);
      return map;
    }).toList();
    return jsonEncode(maps);
  }

}

/// One calculated leg and the waypoint row whose Alt column shows it.
class PlanLegTarget {
  final LatLng from;
  final LatLng to;
  final Waypoint waypoint;
  final int? fixIndex;

  /// Altitude the airplane is already at when this leg begins.
  final int fromAltitudeFt;

  const PlanLegTarget({
    required this.from,
    required this.to,
    required this.waypoint,
    required this.fixIndex,
    required this.fromAltitudeFt,
  });
}

class _DestinationSplit {
  final List<Destination> all;
  final List<Destination> nextBeforeConnect;
  final List<Destination> passed;
  final List<Destination> current;
  final List<Destination> next;
  final Destination active;

  _DestinationSplit({
    required this.all,
    required this.nextBeforeConnect,
    required this.passed,
    required this.current,
    required this.next,
    required this.active,
  });
}
