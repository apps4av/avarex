import 'package:avaremp/constants.dart';
import 'package:avaremp/gdl90/fis_graphics.dart';
import 'package:avaremp/gdl90/product.dart';
import 'package:avaremp/storage.dart' show Storage;
import 'package:avaremp/weather/notam.dart';
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
    else if(fisGraphics.geometryOverlayOptions == FisGraphics.shapeNone) {
      List<String> parts = fisGraphics.text.split(' ');
      if (parts.length > 1) {
        // put in the map so we can combine and retrieve, unique by id
        String id = parts[1];
        // if notam does not exists, make it, otherwise add to already existing
        Notam? notam = Storage().notam.get(fisGraphics.location) as Notam?;
        if(notam == null || notam.source == Weather.sourceInternet) {
          // we have a non ADSB notam, or no notam overwrite
          notam = Notam(fisGraphics.location, DateTime.now().add(
              const Duration(minutes: Constants.weatherUpdateTimeMin)),
              DateTime.now(), Weather.sourceADSB, fisGraphics.text);
          Storage().notam.put(notam);
          return;
        }
        notam.received = DateTime.now();
        notam.expires = DateTime.now().add(const Duration(minutes: Constants.weatherUpdateTimeMin));
        if(notam.text.contains(id)) {
          // throw away we already have it
        }
        else {
          notam.text += "\n\n${fisGraphics.text}";
          Storage().notam.put(notam);
        }
      }
    }
  }
}