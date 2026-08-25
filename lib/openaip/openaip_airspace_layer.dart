import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'openaip_database.dart';

class OpenAipAirspaceLayer {
  OpenAipAirspaceLayer._();

  static List<Polygon> polygons(
    List<OpenAipAirspace> airspaces, {
    required double opacity,
  }) => airspaces.where((airspace) => airspace.points.length >= 3).map((airspace) {
    final color = _classColor(airspace.icaoClass);
    final limits = [
      if (airspace.lowerFeet != null) airspace.lowerFeet!.round(),
      if (airspace.upperFeet != null) airspace.upperFeet!.round(),
    ].join('-');
    final status = airspace.byNotam ? ' BY NOTAM' : airspace.onRequest ? ' ON REQUEST' : '';
    return Polygon(
      points: airspace.points,
      color: color.withValues(alpha: 0.10 * opacity),
      borderColor: color.withValues(alpha: opacity),
      borderStrokeWidth: 2,
      label: '${airspace.name}${limits.isEmpty ? '' : ' $limits ft'}$status',
      labelStyle: TextStyle(
        color: color.withValues(alpha: opacity),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
  }).toList();

  static Color _classColor(int? value) => switch (value) {
    1 => Colors.blue,
    2 => Colors.indigo,
    3 => Colors.purple,
    4 => Colors.red,
    5 => Colors.orange,
    _ => Colors.brown,
  };
}
