import 'package:latlong2/latlong.dart';

class Saa {
  final String designator;
  final String name;
  final String frequencyTx;
  final String frequencyRx;
  final LatLng coordinate;
  final String day;

  Saa({
    required this.designator,
    required this.name,
    required this.frequencyTx,
    required this.frequencyRx,
    required this.coordinate,
    required this.day});

  factory Saa.fromMap(Map<String, dynamic> maps) {
    return Saa(
      designator : maps['designator'] as String,
      name : maps['name'] as String,
      frequencyTx: maps['FreqTx'] as String,
      frequencyRx: maps['FreqRx'] as String,
      day: maps['day'] as String,
      coordinate: LatLng(maps['lat'] as double, maps['lon'] as double));
  }

  @override
  String toString() {
    int cut = day.toLowerCase().indexOf("altitudes. ");
    String abbreviated = day;
    if(cut > 0) {
      abbreviated = day.substring(cut);
    }
    return "$name\nFrequency TX $frequencyTx\nFrequency Rx $frequencyRx\n$abbreviated";
  }
}