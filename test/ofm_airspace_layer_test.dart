import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:avaremp/ofm/ofm_airspace_layer.dart';
import 'package:avaremp/ofm/ofm_data_provider.dart';

void main() {
  test('converts OFM airspace vertices to a labelled polygon', () {
    const airspace = OfmAirspace(
      id: 's', codeId: 'LFBG', name: 'COGNAC', airspaceClass: 'D',
      region: 'LF', cycle: '2601', lowerFeet: 0, upperFeet: 1500,
      vertices: [LatLng(45.7, -0.4), LatLng(45.8, -0.3), LatLng(45.7, -0.2)],
    );
    final polygons = OfmAirspaceLayer.polygons([airspace], opacity: 0.5);

    expect(polygons, hasLength(1));
    expect(polygons.single.points, hasLength(3));
    expect(polygons.single.label, contains('LFBG'));
  });

  test('interpolates clockwise OFMX arc vertices', () {
    const vertices = [
      OfmAirspaceVertex(point: LatLng(45.7, -0.4), codeType: 'GRC'),
      OfmAirspaceVertex(
        point: LatLng(45.8, -0.3),
        codeType: 'CWA',
        arcCenter: LatLng(45.75, -0.35),
      ),
      OfmAirspaceVertex(point: LatLng(45.7, -0.2), codeType: 'GRC'),
    ];

    final points = OfmAirspaceLayer.expandVertices(vertices);

    expect(points.length, greaterThan(3));
    expect(points.first, const LatLng(45.7, -0.4));
    expect(points.last, const LatLng(45.7, -0.2));
  });
}
