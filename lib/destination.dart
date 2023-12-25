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

  double lon;
  double lat;
  final List<Map<String, dynamic>> frequencies;
  final List<Map<String, dynamic>> runways;

  AirportDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required this.lon,
    required this.lat,
    required this.frequencies,
    required this.runways,
  });

}

