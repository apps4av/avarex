import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';

import 'ofm_data_provider.dart';

class OfmAirspaceLayer {
  OfmAirspaceLayer._();

  static List<Polygon> polygons(List<OfmAirspace> airspaces, {required double opacity}) {
    return airspaces.where((airspace) => airspace.vertices.length >= 3).map((airspace) {
      final color = _classColor(airspace.airspaceClass);
      final altitude = [
        if (airspace.lowerFeet != null) '${airspace.lowerFeet!.round()}',
        if (airspace.upperFeet != null) '${airspace.upperFeet!.round()}',
      ].join('-');
      return Polygon(
        points: airspace.geometry.isEmpty ? airspace.vertices : expandVertices(airspace.geometry),
        color: color.withValues(alpha: 0.12 * opacity),
        borderColor: color.withValues(alpha: opacity),
        borderStrokeWidth: 2,
        label: '${airspace.codeId} ${airspace.name}${altitude.isEmpty ? '' : ' $altitude ft'}',
        labelStyle: TextStyle(color: color.withValues(alpha: opacity), fontSize: 10, fontWeight: FontWeight.bold),
      );
    }).toList();
  }

  static List<LatLng> expandVertices(List<OfmAirspaceVertex> vertices) {
    if (vertices.length < 2) return vertices.map((v) => v.point).toList();
    final result = <LatLng>[vertices.first.point];
    for (var index = 1; index < vertices.length; index++) {
      final current = vertices[index];
      final center = current.arcCenter;
      if (center == null || (current.codeType != 'CWA' && current.codeType != 'CCA')) {
        result.add(current.point);
        continue;
      }
      final start = result.last;
      final xScale = cos(center.latitude * pi / 180);
      final sx = (start.longitude - center.longitude) * xScale;
      final sy = start.latitude - center.latitude;
      final ex = (current.point.longitude - center.longitude) * xScale;
      final ey = current.point.latitude - center.latitude;
      final radius = (sqrt(sx * sx + sy * sy) + sqrt(ex * ex + ey * ey)) / 2;
      final startAngle = atan2(sy, sx);
      var endAngle = atan2(ey, ex);
      if (current.codeType == 'CWA') {
        while (endAngle >= startAngle) {
          endAngle -= 2 * pi;
        }
      } else {
        while (endAngle <= startAngle) {
          endAngle += 2 * pi;
        }
      }
      final sweep = endAngle - startAngle;
      final steps = max(2, (sweep.abs() / (5 * pi / 180)).ceil());
      for (var step = 1; step <= steps; step++) {
        final angle = startAngle + sweep * step / steps;
        result.add(LatLng(
          center.latitude + radius * sin(angle),
          center.longitude + radius * cos(angle) / xScale,
        ));
      }
    }
    return result;
  }

  static Color _classColor(String value) {
    switch (value.toUpperCase()) {
      case 'B': return Colors.blue;
      case 'C': return Colors.purple;
      case 'D': return Colors.red;
      case 'E': return Colors.orange;
      default: return Colors.brown;
    }
  }
}
