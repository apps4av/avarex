import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofm_constants.dart';

void main() {
  test('OFM layer name is stable for settings and map rendering', () {
    expect(OfmConstants.layerName, 'OFM VFR Chart');
    expect(OfmConstants.dataLayerName, 'OFM Interactive Data');
  });
}
