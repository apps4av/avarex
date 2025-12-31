import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/main_database_helper.dart';
import '../destination/destination.dart';
import '../utils/geo_calculations.dart';

class FlightStatus {
  static const int flightStateNoChange = 0;
  static const int flightStateLanded = 1;
  static const int flightStateTakeoff = 2;
  static const String phaseTaxi = "Taxi";
  static const String phaseAirborne = "Airborne";
  static const int transitionSpeed = 20;
  int flightTime = 0;

  String phase = phaseTaxi;
  String lastPhase = phaseTaxi;
  final flightStateChange = ValueNotifier<int>(0);


  // speed moving array
  List<double> _speeds = List.generate(10, (int index) {return 0;});

  // landing switches airport diagram to the airport we landed at, if it has an airport diagram
  static Future<void> _land() async {
    // on landing, add to recent the airport we landed at, then set it as current airport
    List<Destination> airports = await MainDatabaseHelper.db.findNearestAirportsWithRunways(
        LatLng(Storage().position.latitude, Storage().position.longitude), 0);
    if (airports.isNotEmpty) {
      String? plate = await PathUtils.getAirportDiagram(Storage().dataDir, airports[0].locationID);
      if (null != plate) {
        Storage().lastPlateAirport = "";
        Storage().plateAirportDestination = airports[0];
        Storage().settings.setCurrentPlateAirport(airports[0].locationID);
        Storage().currentPlate = plate;
        Storage().loadPlate();
      }
    }
  }

  void update (double inSpeed) {
    double q = GeoCalculations.convertSpeed(inSpeed);
    _speeds = _speeds.sublist(1)..add(q);
    double speed = _speeds.reduce((a, b) {return a + b;}) / _speeds.length;

    if(phase == phaseAirborne) {
      flightTime++;
    }

    // calculate flight status used for things like auto load taxi diagram, flight time
    if(phase == phaseTaxi && lastPhase == phaseTaxi && speed > transitionSpeed) {
      // in air
      lastPhase = phase;
      phase = phaseAirborne;
      flightStateChange.value = flightStateNoChange;
      return;
    }
    if(phase == phaseAirborne && lastPhase == phaseAirborne && speed < transitionSpeed) {
      // on ground
      lastPhase = phase;
      phase = phaseTaxi;
      flightStateChange.value = flightStateNoChange;
      return;
    }
    if(phase == phaseTaxi && lastPhase == phaseAirborne) {
      // landed
      lastPhase = phase;

      _land().then((value) {
        flightStateChange.value = flightStateLanded;
      });
      return;
    }
    if(phase == phaseAirborne && lastPhase == phaseTaxi) {
      // takeoff
      lastPhase = phase;
      flightStateChange.value = flightStateTakeoff;
      return;
    }
    lastPhase = phase;
    flightStateChange.value = flightStateNoChange;

  }

  void resetFlightTime() {
    flightTime = 0;
  }

}