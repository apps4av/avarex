import 'package:avaremp/utils/geojson_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Real-world data from COPA_Practice_Areas_v7/KBJC Practice Areas.geojson
// (Colorado pattern practice areas around KBJC).
const String _kbjcPracticeAreas = '''
{
"type": "FeatureCollection",
"name": "KBJC Practice Areas",
"features": [
{ "type": "Feature", "properties": { "Name": "Vollmar Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -104.9385358, 40.1678509, 0.0 ], [ -104.8835597, 40.0977825, 0.0 ], [ -104.8700618, 40.1039691, 0.0 ], [ -104.8556997, 40.1095963, 0.0 ], [ -104.840123, 40.1152284, 0.0 ], [ -104.8249232, 40.1202442, 0.0 ], [ -104.8129092, 40.1240167, 0.0 ], [ -104.796082, 40.1284782, 0.0 ], [ -104.7816775, 40.1320036, 0.0 ], [ -104.7652514, 40.1355111, 0.0 ], [ -104.7492656, 40.1384226, 0.0 ], [ -104.7352071, 40.1409662, 0.0 ], [ -104.7361982, 40.2042963, 0.0 ], [ -104.8495327, 40.2043237, 0.0 ], [ -104.9385358, 40.1678509, 0.0 ] ] ] } },
{ "type": "Feature", "properties": { "Name": "Platteville Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -104.8495302, 40.2043258, 0.0 ], [ -104.736708, 40.2043034, 0.0 ], [ -104.735531, 40.3094325, 0.0 ], [ -104.7665302, 40.3058481, 0.0 ], [ -104.781444, 40.3038787, 0.0 ], [ -104.7971807, 40.301566, 0.0 ], [ -104.817752, 40.298095, 0.0 ], [ -104.8374048, 40.2936982, 0.0 ], [ -104.8500436, 40.2905155, 0.0 ], [ -104.8495302, 40.2043258, 0.0 ] ] ] } },
{ "type": "Feature", "properties": { "Name": "Gowanda Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -104.9388077, 40.1680849, 0.0 ], [ -104.8495302, 40.2043258, 0.0 ], [ -104.849648, 40.2911385, 0.0 ], [ -104.8884756, 40.2805832, 0.0 ], [ -104.9007093, 40.2773626, 0.0 ], [ -104.9122998, 40.2736276, 0.0 ], [ -104.9241724, 40.2694524, 0.0 ], [ -104.9395823, 40.2642986, 0.0 ], [ -104.9555993, 40.2578784, 0.0 ], [ -104.9758052, 40.2497667, 0.0 ], [ -104.9963159, 40.2404212, 0.0 ], [ -104.9388077, 40.1680849, 0.0 ] ] ] } },
{ "type": "Feature", "properties": { "Name": "Jackrabbit Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -104.7928788, 40.3617488, 0.0 ], [ -104.7932606, 40.4389469, 0.0 ], [ -104.9002162, 40.4385109, 0.0 ], [ -104.9008785, 40.3599321, 0.0 ], [ -104.7928788, 40.3617488, 0.0 ] ] ] } },
{ "type": "Feature", "properties": { "Name": "Cattle Sheds Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -104.8737873, 40.2846252, 0.0 ], [ -104.8560635, 40.2893201, 0.0 ], [ -104.8400536, 40.2930601, 0.0 ], [ -104.8231504, 40.2967982, 0.0 ], [ -104.8120275, 40.2988369, 0.0 ], [ -104.7973432, 40.3015537, 0.0 ], [ -104.7826567, 40.3035905, 0.0 ], [ -104.7648504, 40.3063026, 0.0 ], [ -104.7545926, 40.307309, 0.0 ], [ -104.7549532, 40.362333, 0.0 ], [ -104.877096, 40.3598884, 0.0 ], [ -104.8737873, 40.2846252, 0.0 ] ] ] } },
{ "type": "Feature", "properties": { "Name": "Johnstown Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -104.9755662, 40.2498628, 0.0 ], [ -104.956538, 40.2574342, 0.0 ], [ -104.9384956, 40.2645037, 0.0 ], [ -104.9227486, 40.2698408, 0.0 ], [ -104.9046718, 40.2762195, 0.0 ], [ -104.8740288, 40.2847328, 0.0 ], [ -104.8772905, 40.3599109, 0.0 ], [ -104.9790025, 40.3596975, 0.0 ], [ -104.9755662, 40.2498628, 0.0 ] ] ] } },
{ "type": "Feature", "properties": { "Name": "Berthoud Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -105.0628815, 40.2900648, 0.0 ], [ -105.0539465, 40.2835234, 0.0 ], [ -104.9963328, 40.2400291, 0.0 ], [ -104.9870952, 40.2446317, 0.0 ], [ -104.9755687, 40.2499131, 0.0 ], [ -104.9790051, 40.3596995, 0.0 ], [ -105.063638, 40.3601819, 0.0 ], [ -105.0628815, 40.2900648, 0.0 ] ] ] } },
{ "type": "Feature", "properties": { "Name": "Boedecker Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -105.1293731, 40.3688867, 0.0 ], [ -105.1287297, 40.5003204, 0.0 ], [ -105.2069921, 40.4998366, 0.0 ], [ -105.208299, 40.3692765, 0.0 ], [ -105.1293731, 40.3688867, 0.0 ] ] ] } },
{ "type": "Feature", "properties": { "Name": "Lonetree Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -105.0628469, 40.2904074, 0.0 ], [ -105.0642312, 40.369475, 0.0 ], [ -105.1591855, 40.3686029, 0.0 ], [ -105.1583179, 40.2901246, 0.0 ], [ -105.0628469, 40.2904074, 0.0 ] ] ] } },
{ "type": "Feature", "properties": { "Name": "Terry Lake Box" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -105.0631678, 40.2903684, 0.0 ], [ -105.15791, 40.2900654, 0.0 ], [ -105.1568429, 40.2193324, 0.0 ], [ -105.0358059, 40.2202216, 0.0 ], [ -105.0205236, 40.2279616, 0.0 ], [ -105.0089629, 40.234335, 0.0 ], [ -104.9963328, 40.2400291, 0.0 ], [ -105.0631678, 40.2903684, 0.0 ] ] ] } }
]
}
''';

void main() {
  test("KBJC practice area labels keep their full names", () async {
    final GeoJsonParser parser = GeoJsonParser();
    await parser.parse(_kbjcPracticeAreas);

    const names = [
      "Vollmar Box",
      "Platteville Box",
      "Gowanda Box",
      "Jackrabbit Box",
      "Cattle Sheds Box",
      "Johnstown Box",
      "Berthoud Box",
      "Boedecker Box",
      "Lonetree Box",
      "Terry Lake Box",
    ];

    expect(parser.polygons, hasLength(names.length));
    expect(parser.markers, isEmpty);
    // Regression: the old substring(1, length - 2) dropped the final
    // character of every label (e.g. "Name: Vollmar Bo").
    for (var i = 0; i < names.length; i++) {
      expect(parser.polygons[i].label, "Name: ${names[i]}");
    }
  });

  test("features with null properties do not throw RangeError", () async {
    final GeoJsonParser parser = GeoJsonParser();
    await parser.parse(
      '{"type":"Feature","properties":null,"geometry":{"type":"Point","coordinates":[-104.99,40.22]}}',
    );
    expect(parser.markers, hasLength(1));
  });
}
