// destination base class
class Destination {

  final String locationID;
  final String type;
  final String facilityName;

  const Destination({
    required this.locationID,
    required this.type,
    required this.facilityName,
  });
}

class AirportDestination extends Destination {

  final double lon;
  final double lat;
  final List<Map<String, dynamic>> frequencies;
  final List<Map<String, dynamic>> runways;
  final List<Map<String, dynamic>> awos;
  final String unicom;
  final String ctaf;

  AirportDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required this.lon,
    required this.lat,
    required this.frequencies,
    required this.awos,
    required this.runways,
    required this.unicom,
    required this.ctaf
  });

}

