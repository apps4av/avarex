import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:avaremp/weather/terrain_transcode.dart';

void main() {
  group('elevation gray encoding (matches AvareX decoder)', () {
    test('encode/decode round-trips within one quantization step', () {
      for (final ft in [0.0, 500.0, 1000.0, 5280.0, 10000.0, 14000.0]) {
        final g = TerrainTranscode.encodeGray(ft);
        final back = TerrainTranscode.decodeGray(g);
        expect((back - ft).abs(), lessThanOrEqualTo(kElevSlope),
            reason: 'ft=$ft gray=$g back=$back');
      }
    });

    test('clamps out-of-range elevations to byte bounds', () {
      expect(TerrainTranscode.encodeGray(-100000), 0);
      expect(TerrainTranscode.encodeGray(1000000), 255);
    });

    test('gray 5 decodes to ~38 ft (validated against a real US tile)', () {
      expect(TerrainTranscode.decodeGray(5), closeTo(38.0, 1.0));
    });
  });

  group('tile grid (slippy X, TMS Y)', () {
    test('Frankfurt maps to AvareX tile 536/676 at z10', () {
      final x = TerrainTranscode.lonToTileX(8.55, 10);
      final yx = TerrainTranscode.latToTileYXyz(50.03, 10);
      final yTms = (1 << 10) - 1 - yx;
      expect(x, 536);
      expect(yTms, 676);
    });

    test('TerrainTile.yXyz is the TMS complement of yTms', () {
      const t = TerrainTile(10, 536, 676);
      expect(t.yXyz, (1 << 10) - 1 - 676); // 347
    });

    test('tilesForBounds covers all zooms and is non-empty', () {
      final tiles = TerrainTranscode.tilesForBounds(45.8, 47.9, 5.9, 10.6); // CH
      final zooms = tiles.map((t) => t.z).toSet();
      expect(zooms, containsAll(List.generate(10, (i) => i + 1)));
      // count helper agrees with enumeration
      expect(tiles.length,
          TerrainTranscode.countTilesForBounds(45.8, 47.9, 5.9, 10.6));
    });

    test('countTilesForBounds is reasonable for Switzerland', () {
      final n = TerrainTranscode.countTilesForBounds(45.8, 47.9, 5.9, 10.6);
      expect(n, greaterThan(100));
      expect(n, lessThan(400));
    });
  });

  group('terrarium URL', () {
    test('builds the AWS Terrain Tiles URL for slippy XYZ', () {
      final u = TerrainTranscode.terrariumUrl(10, 534, 362);
      expect(u.toString(),
          'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/10/534/362.png');
    });
  });

  group('transcode a real terrarium tile', () {
    test('produces a 512x512 gray+alpha PNG that decodes to Alpine elevations',
        () {
      final bytes = File(
              'test/fixtures/terrarium_alps_10_534_362.png')
          .readAsBytesSync();
      final out = TerrainTranscode.transcodeTerrarium(bytes);
      expect(out, isNotNull);

      final decoded = img.decodePng(Uint8List.fromList(out!));
      expect(decoded, isNotNull);
      expect(decoded!.width, 512);
      expect(decoded.height, 512);

      // Sample the center and decode via AvareX's own formula.
      final p = decoded.getPixel(256, 256);
      final ft = TerrainTranscode.decodeGray(p.r.toInt());
      // This Alps tile ranges ~2000-13000 ft; the center should be high alpine.
      expect(ft, greaterThan(1500));
      expect(ft, lessThan(14000));
      // Alpha present (data), so it renders.
      expect(p.a.toInt(), greaterThan(0));
    });
  });
}
