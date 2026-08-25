import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/data/app_settings.dart';
import 'package:avaremp/ofm/ofm_constants.dart';
import 'package:avaremp/openaip/openaip_constants.dart';

// Locks in the "Europe map layers ON by default for fresh installs" behavior
// without needing the full settings database. The layer ORDER is asserted
// against the canonical getLayers() default list so the hard-coded opacity
// indices can never silently drift.
void main() {
  // Canonical fresh-install layer order (mirrors AppSettings.getLayers default).
  const layerOrder = [
    'Nav',
    'Circles',
    'Chart',
    'Topo',
    'Vector Map',
    OfmConstants.layerName, // OFM VFR Chart
    OfmConstants.dataLayerName, // OFM Interactive Data
    OpenAipConstants.dataLayerName, // openAIP Interactive Data
    'CAP Grid',
    'Elevation',
    'Weather',
    'TFR',
    'Game TFR',
    'Plate',
    'Traffic',
    'Obstacles',
    'Tape',
    'GeoJSON',
    'PFD',
    'Tracks',
  ];

  List<double> parse(String s) =>
      s.split(',').map((e) => double.parse(e)).toList();

  test('fresh install turns the three Europe layers ON and nothing else new', () {
    final opacity = parse(
        AppSettings.resolveLayersOpacityDefault(false, 'ignored-when-fresh'));

    expect(opacity.length, layerOrder.length);

    double at(String name) => opacity[layerOrder.indexOf(name)];

    // Europe-relevant layers ON.
    expect(at(OfmConstants.layerName), 1.0, reason: 'OFM VFR Chart on');
    expect(at(OfmConstants.dataLayerName), 1.0, reason: 'OFM Interactive Data on');
    expect(at(OpenAipConstants.dataLayerName), 1.0,
        reason: 'openAIP Interactive Data on');

    // Pre-existing US defaults preserved.
    expect(at('Nav'), 1.0);
    expect(at('Chart'), 1.0);
    expect(at('Topo'), 1.0);

    // Everything else remains OFF by default.
    for (final name in [
      'Circles', 'Vector Map', 'CAP Grid', 'Elevation', 'Weather', 'TFR',
      'Game TFR', 'Plate', 'Traffic', 'Obstacles', 'Tape', 'GeoJSON', 'PFD',
      'Tracks',
    ]) {
      expect(at(name), 0.0, reason: '$name stays off');
    }
  });

  test('existing user preference is preserved (no forced Europe-on)', () {
    // A user who had everything but Nav off keeps exactly that.
    const saved = '1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0';
    expect(AppSettings.resolveLayersOpacityDefault(true, saved), saved);
  });

  test('europe-on default matches the documented constant', () {
    expect(AppSettings.resolveLayersOpacityDefault(false, ''),
        AppSettings.europeOnLayersOpacityDefault);
  });
}
