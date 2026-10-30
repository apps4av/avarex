import 'package:avaremp/emergency/emergency_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Square glide ring around 40N 100W, closed like getGlideCircle().
final List<LatLng> ring = [
  LatLng(39.8, -100.2),
  LatLng(39.8, -99.8),
  LatLng(40.2, -99.8),
  LatLng(40.2, -100.2),
  LatLng(39.8, -100.2),
];

Map<String, dynamic> runway({
  String le = '18',
  String he = '36',
  String leLat = '40.1',
  String leLon = '-100.0',
  String heLat = '39.5',
  String heLon = '-100.0',
  String length = '3000',
  String? leHeading = '180',
  String? heHeading = '360',
  String surface = 'ASPH-G',
}) {
  return {
    'LEIdent': le,
    'HEIdent': he,
    'LELatitude': leLat,
    'LELongitude': leLon,
    'HELatitude': heLat,
    'HELongitude': heLon,
    'Length': length,
    'Surface': surface,
    if (leHeading != null) 'LEHeadingT': leHeading,
    if (heHeading != null) 'HEHeading': heHeading,
  };
}

EmergencyAirport airport(String id, List<Map<String, dynamic>> runways,
    {LatLng? at, double elevation = 1000, double? variation}) {
  return EmergencyAirport(
    id: id,
    name: id,
    coordinate: at ?? LatLng(40, -100),
    elevationFt: elevation,
    variation: variation,
    ctaf: '122.8',
    unicom: '',
    runways: runways,
  );
}

List<RunwayCandidate> find(List<EmergencyAirport> airports,
    {(double?, double?) wind = (null, null), double? required}) {
  return EmergencyLogic.findCandidates(
    airports: airports,
    glidePolygon: ring,
    position: LatLng(40, -100),
    windFor: (_) => wind,
    requiredLanding: (double elevation, double headwind) => required,
  );
}

void main() {
  group('pointInPolygon', () {
    test('inside and outside', () {
      expect(EmergencyLogic.pointInPolygon(LatLng(40, -100), ring), isTrue);
      expect(EmergencyLogic.pointInPolygon(LatLng(40.3, -100), ring), isFalse);
      expect(EmergencyLogic.pointInPolygon(LatLng(40, -99.5), ring), isFalse);
    });

    test('too few points is never inside', () {
      expect(EmergencyLogic.pointInPolygon(LatLng(40, -100), [LatLng(40, -100), LatLng(40, -100)]), isFalse);
    });
  });

  group('runway heading', () {
    test('uses the published heading of that end', () {
      expect(EmergencyLogic.runwayHeading(runway(leHeading: '183', heHeading: '3'), 'LE', 0), 183);
      expect(EmergencyLogic.runwayHeading(runway(leHeading: '183', heHeading: '3'), 'HE', 0), 3);
    });

    test('high end without its own heading is opposite the low end', () {
      expect(EmergencyLogic.runwayHeading(runway(leHeading: '183', heHeading: null), 'HE', 0), 3);
    });

    test('falls back to ident and variation', () {
      final Map<String, dynamic> r = runway(leHeading: null, heHeading: null, le: '09L', he: '27R');
      expect(EmergencyLogic.runwayHeading(r, 'LE', 5), 95);
      expect(EmergencyLogic.runwayHeading(r, 'HE', -5), 265);
    });

    test('gives up when nothing is usable', () {
      expect(EmergencyLogic.runwayHeading(runway(leHeading: null, heHeading: null, le: 'H1'), 'LE', 0), isNull);
    });
  });

  group('candidates', () {
    test('only the landing threshold has to be inside the ring', () {
      // 18 lands from the north end (inside). The 36 threshold at 39.5N is outside.
      final List<RunwayCandidate> found = find([airport('AAA', [runway()])]);
      expect(found.length, 1);
      expect(found.first.runwayIdent, '18');
      expect(found.first.heading, 180);
    });

    test('skips water and zero length', () {
      final List<RunwayCandidate> found = find([
        airport('W', [runway(surface: 'WATER')]),
        airport('Z', [runway(length: '0')]),
      ]);
      expect(found, isEmpty);
    });

    test('helipad ends are never selected, even with a published heading', () {
      final Map<String, dynamic> pad = runway(le: 'H1', he: 'H2', length: '60', leHeading: '90', heHeading: '270');
      expect(find([airport('PAD', [pad])]), isEmpty);
      // and an airport with only helipads counts as having no runway data
      expect(EmergencyLogic.hasRunwayData(airport('PAD', [pad])), isFalse);
    });

    test('a runway with no end coordinates is placed on the airport', () {
      // like 7N8: no coordinates, no heading, idents 16 and 34, 2420 ft
      final Map<String, dynamic> noCoords = runway(
          le: '16', he: '34', leLat: '', leLon: '', heLat: '', heLon: '', leHeading: null, heHeading: null, length: '2420');
      final List<RunwayCandidate> found = find([airport('7N8', [noCoords], variation: -12)]);
      expect(found.length, 2);
      final RunwayCandidate le = found.firstWhere((c) => c.runwayIdent == '16');
      final RunwayCandidate he = found.firstWhere((c) => c.runwayIdent == '34');
      expect(le.heading, closeTo(148, 0.001)); // 160 magnetic, 12 west
      expect(he.heading, closeTo(328, 0.001));
      // each landing end is half a runway (about 0.2 nm) from the field
      expect(EmergencyLogic.distanceNm(le.threshold, LatLng(40, -100)), closeTo(2420 / 2 / 6076.12, 0.01));
      expect(EmergencyLogic.distanceNm(he.threshold, LatLng(40, -100)), closeTo(2420 / 2 / 6076.12, 0.01));
      // the 16 threshold is north-west of the field, 34 is south-east
      expect(le.threshold.latitude, greaterThan(40));
      expect(he.threshold.latitude, lessThan(40));
    });

    test('a runway with no coordinates and no usable heading is skipped', () {
      final Map<String, dynamic> noCoords = runway(
          le: 'H1', he: 'H2', leLat: '', leLon: '', heLat: '', heLon: '', leHeading: null, heHeading: null);
      expect(find([airport('HP', [noCoords])]), isEmpty);
    });

    test('headwind and crosswind from the wind', () {
      // wind from 180 at 10 kt, runway 18 heading 180 is a direct headwind
      final RunwayCandidate c = find([airport('AAA', [runway()])], wind: (180.0, 10.0)).first;
      expect(c.headwindKt, closeTo(10, 0.01));
      expect(c.crosswindKt.abs(), lessThan(0.01));
      // wind from 270 at 10 kt is all crosswind
      final RunwayCandidate x = find([airport('AAA', [runway()])], wind: (270.0, 10.0)).first;
      expect(x.headwindKt.abs(), lessThan(0.01));
      expect(x.crosswindKt.abs(), closeTo(10, 0.01));
    });
  });

  group('selection', () {
    final Map<String, dynamic> both = runway(
        le: '18', he: '36', leLat: '40.1', heLat: '39.9', heLon: '-100.0');

    test('most headwind wins among long enough runways', () {
      // wind from 360, so 36 is the headwind end
      final List<RunwayCandidate> found = find([airport('AAA', [both])], wind: (360.0, 15.0), required: 2000);
      expect(found.length, 2);
      final RunwaySelection selection = EmergencyLogic.select(found);
      expect(selection.runway!.runwayIdent, '36');
      expect(selection.lessThanIdeal, isFalse);
    });

    test('too short runways are passed over for a long enough one', () {
      final Map<String, dynamic> shortRw = runway(le: '09', he: '27', leHeading: '90', heHeading: '270',
          leLat: '40.0', leLon: '-100.1', heLat: '40.0', heLon: '-99.9', length: '1500');
      final Map<String, dynamic> longRw = runway(length: '4000', heLat: '39.95');
      final List<RunwayCandidate> found = find(
          [airport('SHORT', [shortRw]), airport('LONG', [longRw])],
          wind: (90.0, 20.0),
          required: 2500);
      final RunwaySelection selection = EmergencyLogic.select(found);
      // the 09 end has the headwind but is only 1500 ft
      expect(selection.runway!.airport.id, 'LONG');
      expect(selection.lessThanIdeal, isFalse);
    });

    test('nearest runway breaks a headwind tie', () {
      final Map<String, dynamic> far = runway(leLat: '40.15');
      final Map<String, dynamic> near = runway(leLat: '40.02');
      final List<RunwayCandidate> found = find(
          [airport('FAR', [far]), airport('NEAR', [near])],
          wind: (180.0, 10.0));
      expect(EmergencyLogic.select(found).runway!.airport.id, 'NEAR');
    });

    test('when none is long enough the longest is offered as less than ideal', () {
      final List<RunwayCandidate> found = find([
        airport('A', [runway(length: '1800')]),
        airport('B', [runway(length: '2200', leLat: '40.15')]),
      ], required: 3000);
      final RunwaySelection selection = EmergencyLogic.select(found);
      expect(selection.runway!.airport.id, 'B');
      expect(selection.lessThanIdeal, isTrue);
    });

    test('unknown landing data does not count against a runway', () {
      final List<RunwayCandidate> found = find([airport('A', [runway(length: '500')])]);
      final RunwaySelection selection = EmergencyLogic.select(found);
      expect(selection.runway, isNotNull);
      expect(selection.lessThanIdeal, isFalse);
    });

    test('no runway in the ring', () {
      final RunwaySelection selection = EmergencyLogic.select(find([]));
      expect(selection.runway, isNull);
    });
  });

  group('airports without runway data', () {
    List<RunwayCandidate> noData(List<EmergencyAirport> airports, {(double?, double?) wind = (null, null)}) {
      return EmergencyLogic.findNoDataAirports(
          airports: airports, glidePolygon: ring, position: LatLng(40, -100), windFor: (_) => wind);
    }

    test('an airport with no runway rows is landable into the wind', () {
      final List<RunwayCandidate> found = noData([airport('NODATA', [], at: LatLng(40.1, -100))], wind: (250.0, 12.0));
      expect(found.length, 1);
      expect(found.first.noRunwayData, isTrue);
      expect(found.first.heading, 250);
      expect(found.first.headwindKt, 12);
      expect(found.first.threshold.latitude, 40.1);
    });

    test('without wind the direction is straight to the field', () {
      final RunwayCandidate c = noData([airport('NODATA', [], at: LatLng(40.1, -100))]).first;
      expect(c.heading, closeTo(0, 0.5)); // field is due north
      expect(c.headwindKt, 0);
    });

    test('airports with runway data, or outside the ring, are not included', () {
      expect(noData([airport('HAS', [runway()])]), isEmpty);
      expect(noData([airport('FAR', [], at: LatLng(41, -100))]), isEmpty);
    });

    test('used only when there is no runway', () {
      final List<RunwayCandidate> none = noData([
        airport('FAR', [], at: LatLng(40.15, -100)),
        airport('NEAR', [], at: LatLng(40.05, -100)),
      ]);
      final RunwaySelection last = EmergencyLogic.select([], noData: none);
      expect(last.runway!.airport.id, 'NEAR');
      expect(last.lessThanIdeal, isTrue);
      // a real runway always wins
      final RunwaySelection real = EmergencyLogic.select(find([airport('AAA', [runway()])]), noData: none);
      expect(real.runway!.airport.id, 'AAA');
      expect(real.runway!.noRunwayData, isFalse);
    });
  });

  group('no runway direction', () {
    test('always directly into the wind', () {
      final OffFieldDirection d = EmergencyLogic.offFieldDirection(windFromDeg: 250, windSpeedKt: 12, trackDeg: 90);
      expect(d.intoWind, isTrue);
      expect(d.heading, 250);
      expect(d.label, 'Into wind 250');
    });

    test('current track when there is no wind data', () {
      final OffFieldDirection d = EmergencyLogic.offFieldDirection(windFromDeg: null, windSpeedKt: null, trackDeg: 90);
      expect(d.intoWind, isFalse);
      expect(d.heading, 90);
      final OffFieldDirection calm = EmergencyLogic.offFieldDirection(windFromDeg: 250, windSpeedKt: 0, trackDeg: 45);
      expect(calm.intoWind, isFalse);
      expect(calm.heading, 45);
    });
  });

  group('airspeed', () {
    test('no wind uses ground speed', () {
      expect(
          EmergencyLogic.indicatedAirspeedKt(groundSpeedKt: 65, trackDeg: 90, altitudeFt: 0), closeTo(65, 0.001));
    });

    test('tailwind is taken out', () {
      // 80 kt over the ground heading 360 with a 20 kt wind from 180 is 60 kt true
      expect(
          EmergencyLogic.indicatedAirspeedKt(
              groundSpeedKt: 80, trackDeg: 360, altitudeFt: 0, windFromDeg: 180, windSpeedKt: 20),
          closeTo(60, 0.001));
    });

    test('indicated is lower than true at altitude', () {
      expect(
          EmergencyLogic.indicatedAirspeedKt(groundSpeedKt: 66, trackDeg: 0, altitudeFt: 5000), closeTo(60, 0.001));
    });

    test('blink only when more than 5 knots off', () {
      expect(EmergencyLogic.airspeedOff(70, 65), isFalse);
      expect(EmergencyLogic.airspeedOff(70.1, 65), isTrue);
      expect(EmergencyLogic.airspeedOff(59.9, 65), isTrue);
      expect(EmergencyLogic.airspeedOff(60, 65), isFalse);
    });
  });
}
