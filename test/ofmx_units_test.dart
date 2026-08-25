import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofmx_units.dart';

void main() {
  group('OFMX units', () {
    test('parses hemisphere-suffixed coordinates', () {
      expect(parseOfmCoordinate('51.18945833N'), closeTo(51.18945833, 0.000000001));
      expect(parseOfmCoordinate('004.46039722E'), closeTo(4.46039722, 0.000000001));
      expect(parseOfmCoordinate('002.10675400W'), closeTo(-2.106754, 0.000000001));
      expect(parseOfmCoordinate('12.5S'), -12.5);
    });

    test('rejects invalid coordinates safely', () {
      expect(parseOfmCoordinateOrNull(null), isNull);
      expect(parseOfmCoordinateOrNull(''), isNull);
      expect(parseOfmCoordinateOrNull('91N'), isNull);
      expect(parseOfmCoordinateOrNull('-2W'), isNull);
      expect(parseOfmCoordinateOrNull('NaNN'), isNull);
      expect(() => parseOfmCoordinate('invalid'), throwsFormatException);
    });

    test('normalizes flight levels and metric distances to feet', () {
      expect(ofmAltitudeFeet(115, 'FL'), 11500);
      expect(ofmAltitudeFeet(1000, 'M'), closeTo(3280.839895, 0.000001));
      expect(ofmLengthFeet(1510, 'M'), closeTo(4954.06824, 0.00001));
      expect(ofmLengthFeet(4500, 'FT'), 4500);
    });
  });
}
