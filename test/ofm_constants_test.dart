import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofm_constants.dart';

void main() {
  test('OFM constants include required attribution and disclaimer wording', () {
    expect(OfmConstants.sourceName, 'OpenFlightMaps');
    expect(OfmConstants.attribution.toLowerCase(), contains('open flightmaps'));
    expect(OfmConstants.disclaimer.toLowerCase(), contains('complementary'));
    expect(OfmConstants.disclaimer.toLowerCase(), contains('not a primary navigation source'));
    expect(OfmConstants.corrections.toLowerCase(), contains('report'));
  });
}
