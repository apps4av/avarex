// destination base class

import 'package:latlong2/latlong.dart';

class Destination {

  final String locationID;
  final String type;
  final String facilityName;
  final LatLng coordinate;

  const Destination({
    required this.locationID,
    required this.type,
    required this.facilityName,
    required this.coordinate,
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
    required super.coordinate,
    required this.elevation,
    required this.frequencies,
    required this.awos,
    required this.runways,
    required this.unicom,
    required this.ctaf
  });
}

