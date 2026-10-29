import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each built-in aircraft has cruise, endurance, glide, and climb', () {
    for (final AircraftPerformanceData aircraft in CommonAircraftData.all) {
      expect(aircraft.cruiseSpeedKt, greaterThan(0), reason: aircraft.name);
      expect(aircraft.fuelEnduranceHr, greaterThan(0), reason: aircraft.name);
      expect(aircraft.bestGlideKt, greaterThan(0), reason: aircraft.name);
      expect(aircraft.sinkRateFpm, greaterThan(0), reason: aircraft.name);
      expect(aircraft.bestClimbKt, greaterThan(0), reason: aircraft.name);
      expect(aircraft.bestClimbFpm, greaterThan(0), reason: aircraft.name);
    }
    expect(CommonAircraftData.all, hasLength(10));
  });

  test('Cessna 172S uses its POH cruise, glide, and climb', () {
    final AircraftPerformanceData aircraft = CommonAircraftData.cessna172sp;
    expect(aircraft.cruiseSpeedKt, 124);
    expect(aircraft.fuelEnduranceHr, 5.5);
    expect(aircraft.bestGlideKt, 68);
    expect(aircraft.sinkRateFpm, 756);
    expect(aircraft.bestClimbKt, 74);
    expect(aircraft.bestClimbFpm, 730);
  });
}
