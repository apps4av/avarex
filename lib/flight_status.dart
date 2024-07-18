import 'geo_calculations.dart';

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

  // speed moving array
  List<double> _speeds = List.generate(10, (int index) {return 0;});

  int update (double inSpeed) {
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
      return flightStateNoChange;
    }
    if(phase == phaseAirborne && lastPhase == phaseAirborne && speed < transitionSpeed) {
      // on ground
      lastPhase = phase;
      phase = phaseTaxi;
      return flightStateNoChange;
    }
    if(phase == phaseTaxi && lastPhase == phaseAirborne) {
      // landed
      lastPhase = phase;
      return flightStateLanded;
    }
    if(phase == phaseAirborne && lastPhase == phaseTaxi) {
      // takeoff
      lastPhase = phase;
      return flightStateTakeoff;
    }
    lastPhase = phase;
    return flightStateNoChange;

  }

  void resetFlightTime() {
    flightTime = 0;
  }

}