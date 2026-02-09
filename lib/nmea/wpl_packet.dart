import 'package:avaremp/nmea/packet.dart';

class WPLPacket extends Packet {
  static const String _tag = '\$GPWPL';

  WPLPacket(double latitude, double longitude, String waypointName) {
    packet = '$_tag,';
    packet += _formatLat(latitude);
    packet += ',';
    packet += _formatLon(longitude);
    packet += ',';
    packet += waypointName;
    assemble();
  }

  static String _formatLat(double latitude) {
    final String hemisphere = latitude >= 0 ? 'N' : 'S';
    final double value = latitude.abs();
    final int degrees = value.floor();
    final double minutes = (value - degrees) * 60.0;
    final String minutesText = minutes.toStringAsFixed(4).padLeft(7, '0');
    return '${degrees.toString().padLeft(2, '0')}$minutesText,$hemisphere';
  }

  static String _formatLon(double longitude) {
    final String hemisphere = longitude >= 0 ? 'E' : 'W';
    final double value = longitude.abs();
    final int degrees = value.floor();
    final double minutes = (value - degrees) * 60.0;
    final String minutesText = minutes.toStringAsFixed(4).padLeft(7, '0');
    return '${degrees.toString().padLeft(3, '0')}$minutesText,$hemisphere';
  }
}