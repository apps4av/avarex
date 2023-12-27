// destination base class
class Destination {

  final String locationID;
  final String type;
  final String facilityName;
  final double lon;
  final double lat;

  const Destination({
    required this.locationID,
    required this.type,
    required this.facilityName,
    required this.lon,
    required this.lat,
  });
}

class AirportDestination extends Destination {

  final double elevation;
  final List<Map<String, dynamic>> frequencies;
  final List<Map<String, dynamic>> runways;
  final List<Map<String, dynamic>> awos;
  final String unicom;
  final String ctaf;

  AirportDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required super.lon,
    required super.lat,
    required this.elevation,
    required this.frequencies,
    required this.awos,
    required this.runways,
    required this.unicom,
    required this.ctaf
  });

}

