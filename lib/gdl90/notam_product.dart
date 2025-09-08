import 'package:avaremp/gdl90/fis_graphics.dart';
import 'package:avaremp/gdl90/product.dart';
import 'package:avaremp/storage.dart' show Storage;
import 'package:avaremp/weather/tfr.dart';
import 'package:avaremp/weather/weather.dart';

class NotamProduct extends Product {
  NotamProduct(super.time, super.line, super.coordinate, super.productFileId, super.productFileLength, super.apduNumber, super.segFlag);

  @override
  void parse() {
    super.parse();
    if(fisGraphics.geometryOverlayOptions == FisGraphics.shapePolygonMSL && fisGraphics.coordinates.isNotEmpty) {
      // TFR
      DateTime endsDt;
      DateTime startsDt;
      try {
        endsDt = DateTime.parse(fisGraphics.endTime);
      } catch (e) {
        endsDt=DateTime(2099); // need end time
      }

      try {
        startsDt = DateTime.parse(fisGraphics.startTime);
      } catch (e) {
        startsDt=DateTime(2000); // need end time
      }

      Tfr t = Tfr("ADSB${fisGraphics.reportNumber}",
          endsDt,
          DateTime.now(),
          Weather.sourceADSB,
          fisGraphics.coordinates,
          fisGraphics.altitudeTop,
          fisGraphics.altitudeBottom,
          startsDt.millisecondsSinceEpoch,
          endsDt.millisecondsSinceEpoch,
          0);
      Storage().tfr.put(t);
    }
  }
}