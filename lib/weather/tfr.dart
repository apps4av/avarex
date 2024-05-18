import 'package:avaremp/weather/weather.dart';
import 'package:latlong2/latlong.dart';

class Tfr extends Weather {
  final List<LatLng> coordinates;
  final String upperAltitude;
  final String lowerAltitude;
  final int msEffective;
  final int msExpires;
  final int labelCoordinate;

  Tfr(super.station, super.expires, this.coordinates, this.upperAltitude, this.lowerAltitude, this.msEffective, this.msExpires, this.labelCoordinate);

  @override
  String toString() {
    return
      "Top $upperAltitude\n"
      "Low $lowerAltitude\n"
      "${DateTime.fromMillisecondsSinceEpoch(msEffective).toString().replaceAll(":00.000", "Z")} to\n"
      "${DateTime.fromMillisecondsSinceEpoch(msExpires).toString().replaceAll(":00.000", "Z")}";
  }

  bool isInEffect() {
    int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return (now >= msEffective && now <= msExpires);
  }


  bool isRelevant() {
    return DateTime.now().toUtc().millisecondsSinceEpoch < msExpires;
  }

  int getLabelCoordinate() {
    return labelCoordinate;
  }
}

