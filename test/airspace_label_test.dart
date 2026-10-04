// Evaluates the vector-tile label expressions against property values taken
// from real nasr.mbtiles features, using the same parser the map renderer
// uses. A malformed expression is otherwise silent: the renderer drops it and
// the label simply never appears.
import 'package:avaremp/utils/mbtiles_layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile_renderer/src/model/tile_model.dart'
    show TileFeatureType;
import 'package:vector_tile_renderer/src/themes/expression/expression.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show Logger;

String eval(List<dynamic> expression, Map<String, dynamic> properties) {
  const logger = Logger.noop();
  final parsed = ExpressionParser(logger).parseOptional(expression);
  expect(parsed, isNotNull, reason: 'expression failed to parse: $expression');
  final context = EvaluationContext(
    () => properties,
    TileFeatureType.point,
    logger,
    zoom: 10,
    zoomScaleFactor: 1,
    hasImage: (_) => false,
  );
  return parsed!.evaluate(context).toString();
}

Map<String, dynamic> sua({
  required String lowerLimit,
  required String lowerRef,
  required String lowerUom,
  required String upperLimit,
  required String upperRef,
  required String upperUom,
  String name = 'TEST',
}) =>
    {
      'NAME': name,
      'LOWER_LIMIT': lowerLimit,
      'LOWER_REF': lowerRef,
      'LOWER_UOM': lowerUom,
      'UPPER_LIMIT': upperLimit,
      'UPPER_REF': upperRef,
      'UPPER_UOM': upperUom,
    };

void main() {
  group('class airspace label', () {
    test('surface sector prints SFC', () {
      expect(
        eval(MBTilesLayerManager.classAltitudeLabel(),
            {'UPPER_VAL': '10000', 'LOWER_VAL': '0', 'LOWER_CODE': 'SFC'}),
        '10000/SFC',
      );
    });

    test('shelf prints ceiling over floor', () {
      expect(
        eval(MBTilesLayerManager.classAltitudeLabel(),
            {'UPPER_VAL': '10000', 'LOWER_VAL': '4800', 'LOWER_CODE': 'MSL'}),
        '10000/4800',
      );
    });
  });

  group('special use airspace label', () {
    final label = MBTilesLayerManager.suaAltitudeLabel();

    test('surface to unlimited', () {
      expect(
        eval(label, sua(
          lowerLimit: 'GND', lowerRef: 'SFC', lowerUom: 'FT',
          upperLimit: 'UNL', upperRef: 'OTHER', upperUom: 'OTHER')),
        'UNL/SFC',
      );
    });

    test('zero-padded AGL floor and MSL ceiling', () {
      expect(
        eval(label, sua(
          lowerLimit: '01000', lowerRef: 'SFC', lowerUom: 'FT',
          upperLimit: '05000', upperRef: 'MSL', upperUom: 'FT')),
        '5000/1000 AGL',
      );
    });

    test('flight levels', () {
      expect(
        eval(label, sua(
          lowerLimit: '180', lowerRef: 'STD', lowerUom: 'FL',
          upperLimit: '240', upperRef: 'STD', upperUom: 'FL')),
        'FL240/FL180',
      );
    });

    test('numeric zero floor is SFC', () {
      expect(
        eval(label, sua(
          lowerLimit: '0', lowerRef: 'SFC', lowerUom: 'FT',
          upperLimit: '10000', upperRef: 'MSL', upperUom: 'FT')),
        '10000/SFC',
      );
    });

    test('blank reference with feet is treated as MSL', () {
      expect(
        eval(label, sua(
          lowerLimit: '1200', lowerRef: 'MSL', lowerUom: 'FT',
          upperLimit: '4000', upperRef: '', upperUom: 'FT')),
        '4000/1200',
      );
    });

    test('full label puts name on first line', () {
      expect(
        eval(MBTilesLayerManager.suaLabel(), sua(
          name: 'R-2508 COMPLEX, CA',
          lowerLimit: '01000', lowerRef: 'SFC', lowerUom: 'FT',
          upperLimit: '180', upperRef: 'STD', upperUom: 'FL')),
        'R-2508 COMPLEX, CA\nFL180/1000 AGL',
      );
    });
  });
}
