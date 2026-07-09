import 'package:avaremp/airport_satellite.dart';
import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('AirportSatellite georef EXIF', () {
    test('UserComment round-trips through the injected PNG eXIf chunk', () async {
      final img.Image image = img.Image(width: 16, height: 16);
      const String userComment = "42000.5|-42000.5|-71.123|42.987";

      final bytes = AirportSatellite.encodePngWithGeoref(image, userComment);

      // the exif reader used by Storage.loadPlate must be able to read it back
      final Map<String, IfdTag> exif = await readExifFromBytes(bytes);
      final IfdTag? tag = exif["EXIF UserComment"];

      expect(tag, isNotNull);
      final List<String> tokens = tag.toString().split("|");
      expect(tokens.length, 4);
      expect(double.parse(tokens[0]), 42000.5);
      expect(double.parse(tokens[1]), -42000.5);
      expect(double.parse(tokens[2]), -71.123);
      expect(double.parse(tokens[3]), 42.987);
    });

    test('output is still a valid decodable PNG', () {
      final img.Image image = img.Image(width: 8, height: 8);
      final bytes = AirportSatellite.encodePngWithGeoref(image, "1|1|0|0");
      final decoded = img.decodePng(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 8);
      expect(decoded.height, 8);
    });
  });
}
