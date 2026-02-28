import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import 'package:universal_io/io.dart';

class KmlTrackPoint {
  final LatLng coordinate;
  final double altitude;
  final double heading;
  final double speed;
  final DateTime? time;

  KmlTrackPoint({
    required this.coordinate,
    required this.altitude,
    this.heading = 0,
    this.speed = 0,
    this.time,
  });
}

class KmlTrack {
  final String name;
  final List<KmlTrackPoint> points;
  final double minAltitude;
  final double maxAltitude;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  KmlTrack({
    required this.name,
    required this.points,
    required this.minAltitude,
    required this.maxAltitude,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  LatLng get center => LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
}

class KmlParser {
  static Future<KmlTrack?> parseFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      final content = await file.readAsString();
      return parse(content);
    } catch (e) {
      return null;
    }
  }

  static KmlTrack? parse(String kmlContent) {
    try {
      final document = XmlDocument.parse(kmlContent);
      final root = document.rootElement;
      
      String name = 'Flight Track';
      List<KmlTrackPoint> points = [];

      final nameElements = root.findAllElements('name');
      if (nameElements.isNotEmpty) {
        name = nameElements.first.innerText;
      }

      for (final coordsElement in root.findAllElements('coordinates')) {
        final parent = coordsElement.parent;
        if (parent != null && parent is XmlElement && parent.name.local == 'LineString') {
          final coordsText = coordsElement.innerText.trim();
          final coordLines = coordsText.split(RegExp(r'[\s\n]+'));
          
          for (final line in coordLines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            
            final parts = trimmed.split(',');
            if (parts.length >= 2) {
              final lon = double.tryParse(parts[0].trim());
              final lat = double.tryParse(parts[1].trim());
              final alt = parts.length > 2 ? double.tryParse(parts[2].trim()) : null;
              
              if (lon != null && lat != null) {
                points.add(KmlTrackPoint(
                  coordinate: LatLng(lat, lon),
                  altitude: alt ?? 0.0,
                ));
              }
            }
          }
          
          if (points.isNotEmpty) break;
        }
      }

      if (points.isEmpty) {
        for (final coordsElement in root.findAllElements('coordinates')) {
          final coordsText = coordsElement.innerText.trim();
          final coordLines = coordsText.split(RegExp(r'[\s\n]+'));
          
          for (final line in coordLines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            
            final parts = trimmed.split(',');
            if (parts.length >= 2) {
              final lon = double.tryParse(parts[0].trim());
              final lat = double.tryParse(parts[1].trim());
              final alt = parts.length > 2 ? double.tryParse(parts[2].trim()) : null;
              
              if (lon != null && lat != null) {
                points.add(KmlTrackPoint(
                  coordinate: LatLng(lat, lon),
                  altitude: alt ?? 0.0,
                ));
              }
            }
          }
          
          if (points.isNotEmpty) break;
        }
      }

      if (points.isEmpty) {
        return null;
      }

      Map<int, Map<String, dynamic>> extendedData = {};
      Map<int, DateTime> timestamps = {};
      
      for (final placemark in root.findAllElements('Placemark')) {
        final placemarkName = placemark.findElements('name').firstOrNull?.innerText ?? '';
        final match = RegExp(r'Point (\d+)').firstMatch(placemarkName);
        if (match != null) {
          final pointIndex = int.parse(match.group(1)!) - 1;
          
          final extData = placemark.findElements('ExtendedData').firstOrNull;
          if (extData != null) {
            double heading = 0;
            double speed = 0;
            
            for (final data in extData.findElements('Data')) {
              final dataName = data.getAttribute('name');
              final value = data.findElements('value').firstOrNull?.innerText;
              if (dataName == 'heading' && value != null) {
                heading = double.tryParse(value) ?? 0;
              } else if (dataName == 'speed' && value != null) {
                speed = double.tryParse(value) ?? 0;
              }
            }
            
            extendedData[pointIndex] = {'heading': heading, 'speed': speed};
          }
          
          final timeStamp = placemark.findElements('TimeStamp').firstOrNull;
          if (timeStamp != null) {
            final when = timeStamp.findElements('when').firstOrNull?.innerText;
            if (when != null) {
              final time = DateTime.tryParse(when);
              if (time != null) {
                timestamps[pointIndex] = time;
              }
            }
          }
        }
      }

      for (int i = 0; i < points.length; i++) {
        final ext = extendedData[i];
        final time = timestamps[i];
        if (ext != null || time != null) {
          points[i] = KmlTrackPoint(
            coordinate: points[i].coordinate,
            altitude: points[i].altitude,
            heading: ext?['heading'] ?? 0.0,
            speed: ext?['speed'] ?? 0.0,
            time: time,
          );
        }
      }

      double minAlt = double.infinity;
      double maxAlt = double.negativeInfinity;
      double minLat = double.infinity;
      double maxLat = double.negativeInfinity;
      double minLon = double.infinity;
      double maxLon = double.negativeInfinity;

      for (final p in points) {
        if (p.altitude < minAlt) minAlt = p.altitude;
        if (p.altitude > maxAlt) maxAlt = p.altitude;
        if (p.coordinate.latitude < minLat) minLat = p.coordinate.latitude;
        if (p.coordinate.latitude > maxLat) maxLat = p.coordinate.latitude;
        if (p.coordinate.longitude < minLon) minLon = p.coordinate.longitude;
        if (p.coordinate.longitude > maxLon) maxLon = p.coordinate.longitude;
      }

      if (minAlt == double.infinity) minAlt = 0;
      if (maxAlt == double.negativeInfinity) maxAlt = 0;

      return KmlTrack(
        name: name,
        points: points,
        minAltitude: minAlt,
        maxAltitude: maxAlt,
        minLat: minLat,
        maxLat: maxLat,
        minLon: minLon,
        maxLon: maxLon,
      );
    } catch (e) {
      return null;
    }
  }
}
