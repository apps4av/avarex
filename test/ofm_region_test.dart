import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofm_region.dart';

void main() {
  test('maps download-page codes to OFM publication service identifiers', () {
    expect(OfmRegions.publicationCode('ES'), 'ESAA');
    expect(OfmRegions.publicationCode('EB'), 'EBBU');
    expect(OfmRegions.publicationCode('ED'), 'ED');
    expect(OfmRegions.publicationCode('LO'), 'LOVV');
  });

  test('finds region labels by public download code', () {
    expect(OfmRegions.byCode('ES').name, 'Sweden');
    expect(OfmRegions.byCode('ES').publicationCode, 'ESAA');
  });
}
