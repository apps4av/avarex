import 'package:avaremp/constants.dart';
import 'package:avaremp/gdl90/fis_graphics.dart';
import 'package:avaremp/gdl90/product.dart';
import 'package:avaremp/storage.dart' show Storage;
import 'package:avaremp/weather/notam.dart';
import 'package:avaremp/weather/weather.dart';

/// FIS-B product 10 — Terminal Weather Information for Pilots (TWGO text).
class TwipProduct extends Product {
  TwipProduct(super.time, super.data, super.coordinate, super.productFileId, super.productFileLength, super.apduNumber, super.segFlag);

  @override
  void parse() {
    super.parse();
    if (!fisGraphics.valid) {
      return;
    }
    _storeText("TWIP");
  }

  void _storeText(String label) {
    if (fisGraphics.geometryOverlayOptions != FisGraphics.shapeNone) {
      return;
    }
    final String body = fisGraphics.text.replaceAll("\n", " ").trim();
    if (body.isEmpty || fisGraphics.location.isEmpty) {
      return;
    }
    final String tagged = "$label $body";
    Notam? notam = Storage().notam.get(fisGraphics.location) as Notam?;
    if (notam == null || notam.source == Weather.sourceInternet) {
      notam = Notam(
        fisGraphics.location,
        DateTime.now().add(const Duration(minutes: Constants.weatherUpdateTimeMin)),
        DateTime.now(),
        Weather.sourceADSB,
        tagged,
      );
      Storage().notam.put(notam);
      return;
    }
    notam.received = DateTime.now();
    notam.expires = DateTime.now().add(const Duration(minutes: Constants.weatherUpdateTimeMin));
    if (notam.text.contains(body)) {
      return;
    }
    notam.text += "\n$tagged";
    Storage().notam.put(notam);
  }

  @override
  String decode() => graphicsSummary("TWIP");

  @override
  String shortName() => "TWIP";
}
