import 'dart:convert';

import 'package:avaremp/weather/weather.dart';
import 'package:latlong2/latlong.dart';

class Tfr extends Weather {
  final List<LatLng> coordinates;
  final String upperAltitude;
  final String lowerAltitude;
  final int msEffective;
  final int msExpires;
  final int labelCoordinate;

  Tfr(super.station, super.expires, super.recieved, super.source, this.coordinates, this.upperAltitude, this.lowerAltitude, this.msEffective, this.msExpires, this.labelCoordinate);

  @override
  String toString() {
    return
      "${super.toString()}Top $upperAltitude\nLow $lowerAltitude\n${DateTime.fromMillisecondsSinceEpoch(msEffective).toString().replaceAll(":00.000", "Z")} to\n${DateTime.fromMillisecondsSinceEpoch(msExpires).toString().replaceAll(":00.000", "Z")}";
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


  Map<String, Object?> toMap() {

    List<List<double>> ll = [];
    for(LatLng c in coordinates) {
      ll.add([c.latitude, c.longitude]);
    }

    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "receivedMs": received.millisecondsSinceEpoch,
      "source": source,
      "coordinates": jsonEncode(ll),
      "upperAltitude": upperAltitude,
      "lowerAltitude": lowerAltitude,
      "msEffective": msEffective,
      "msExpires": msExpires,
      "labelCoordinate": labelCoordinate
    };
    return map;
  }

  factory Tfr.fromMap(Map<String, dynamic> maps) {

    List<LatLng> ll = [];
    List<dynamic> coordinates = jsonDecode(maps['coordinates'] as String);
    for(dynamic coordinate in coordinates) {
      ll.add(LatLng(coordinate[0], coordinate[1]));
    }

    return Tfr(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      DateTime.fromMillisecondsSinceEpoch(maps['receivedMs'] as int),
      maps['source'] as String,
      ll,
      maps['upperAltitude'] as String,
      maps['lowerAltitude'] as String,
      maps['msEffective'] as int,
      maps['msExpires'] as int,
      maps['labelCoordinate'] as int
    );
  }

}

/// One TFR altitude. [agl] is height above the ground. Otherwise the feet are MSL.
class TfrLevel {
  final double feet;
  final bool unlimited;
  final bool agl;

  const TfrLevel(this.feet, {this.unlimited = false, this.agl = false});
}

/// `400` ft above the ground is `400 AGL`. `17999` ft MSL is `17999 MSL`.
String formatTfrAltitude(num feet, {required bool agl}) {
  final shown = feet == feet.roundToDouble() ? feet.round().toString() : feet.toString();
  return '$shown ${agl ? 'AGL' : 'MSL'}';
}

/// FAA XML limit. `HEI` is AGL and `ALT` is MSL. Flight levels are hundreds of feet.
String formatTfrLimit(String value, String code, String uom) {
  final text = value.trim();
  final upper = text.toUpperCase();
  if (upper.isEmpty || upper.contains('NOTAM')) {
    return text.isEmpty ? 'Check NOTAMs' : text;
  }
  if (upper.contains('AGL') || upper.contains('MSL')) {
    return text;
  }
  if (upper == 'UNL' || upper == 'UNLIMITED') {
    return 'UNL';
  }
  final reference = code.trim().toUpperCase();
  final agl = reference == 'HEI' || reference == 'AGL';
  final msl = reference == 'ALT' || reference == 'MSL';
  var number = upper;
  if (number == 'SFC' || number == 'GND' || number == 'SURFACE') {
    number = '0';
  }
  final parsed = double.tryParse(number.replaceAll(',', ''));
  if (parsed == null) {
    return text;
  }
  final unit = uom.trim().toUpperCase();
  final feet = unit == 'FL' ? parsed * 100 : parsed;
  if (!agl && !msl) {
    return feet == feet.roundToDouble() ? feet.round().toString() : feet.toString();
  }
  return formatTfrAltitude(feet, agl: agl);
}

/// Feet to draw. AGL is added to the ground, even when the ground is above the shelf scale.
double tfrLevelFeet(double feet, {required bool agl, required double groundFt}) {
  final ground = groundFt.isFinite && groundFt > 0 ? groundFt : 0.0;
  if (agl) {
    return ground + (feet.isFinite && feet > 0 ? feet : 0);
  }
  return feet.isFinite ? feet : 0;
}

/// The floor is already at or above the top of the 3D picture, so the volume is not in frame.
bool tfrAboveScale(TfrLevel? floor, double scaleFt) {
  if (floor == null || floor.unlimited || !scaleFt.isFinite || scaleFt <= 0) {
    return false;
  }
  return floor.feet >= scaleFt;
}

/// Feet from a stored TFR altitude. A bare `050` is 5000 ft MSL. `400 AGL` is 400 ft above the ground.
TfrLevel? parseTfrLevel(String raw) {
  final original = raw.trim().toUpperCase();
  if (original.isEmpty || original.contains('NOTAM')) {
    return null;
  }
  final bool? reference = original.contains('AGL') || original.contains('HEI')
      ? true
      : (original.contains('MSL') || RegExp(r'\bALT\b').hasMatch(original) ? false : null);
  var text = original
      .replaceAll(RegExp(r'\b(AGL|MSL|HEI|ALT|FT|FEET)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text == 'UNL' || text == 'UNLIMITED' || (reference == null && text == '999')) {
    return TfrLevel(0, unlimited: true, agl: reference ?? false);
  }
  final flightLevel = RegExp(r'^FL\s*(\d+)$').firstMatch(text);
  if (flightLevel != null) {
    return TfrLevel(double.parse(flightLevel.group(1)!) * 100, agl: reference ?? false);
  }
  if (text == 'SFC' || text == 'GND' || text == 'SURFACE') {
    return TfrLevel(0, agl: reference ?? true);
  }
  if (text == '0') {
    return TfrLevel(0, agl: reference ?? false);
  }
  final value = double.tryParse(text.replaceAll(',', ''));
  if (value == null) {
    return null;
  }
  if (reference == null && value > 0 && value <= 180 && !text.contains('.') && text.length <= 3) {
    return TfrLevel(value * 100);
  }
  return TfrLevel(value, agl: reference ?? false);
}

