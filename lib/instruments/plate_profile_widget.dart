import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:avaremp/constants.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/airport.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';

const double _metersToNm = 0.000539957;

class PlateProfileWidget extends StatefulWidget {

  final String selectedProcedure;

  const PlateProfileWidget({required this.selectedProcedure,
    super.key});

  @override
  State<StatefulWidget> createState() => PlateProfileWidgetState();
}

class PlateProfileWidgetState extends State<PlateProfileWidget> {

  final Distance _profileDistance = const Distance(calculator: Haversine());
  final List<_VerticalProfilePoint> _points = [];
  int _loadId = 0;
  ValueNotifier<int> notifier = ValueNotifier(0);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: loadProfile(widget.selectedProcedure),
      builder: (context, snapshot) {
        return _buildProfile(context);
      },
    );
  }

  Widget _buildProfile(BuildContext context) {

    if (_points.isEmpty) {
      return Container();
    }
    final double screenHeight = Constants.screenHeight(context);
    final double screenWidth = Constants.screenWidth(context);
    final double height = max(120, screenHeight * (Constants.isPortrait(context) ? 0.22 : 0.3));
    final double width = screenWidth * 0.5;
    final Color background = Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8);
    final Color textColor = Theme.of(context).colorScheme.onSurface;
    final Color axisColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    final Color lineColor = Theme.of(context).colorScheme.secondary;
    final Color planeColor = Constants.planeColor.withValues(alpha: 0.9);

    return Positioned(
      child: Align(
        alignment: Alignment.bottomRight,
        child: IgnorePointer(
          child: Padding(
            padding: EdgeInsets.only(bottom: Constants.bottomPaddingSize(context) + 60),
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: axisColor),
              ),
              child: CustomPaint(
                painter: _VerticalProfilePainter(
                  notifier,
                  _points,
                  label: widget.selectedProcedure,
                  textColor: textColor,
                  axisColor: axisColor,
                  lineColor: lineColor,
                  planeColor: planeColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> loadProfile(String procedureName) async {
    final int loadId = ++_loadId;
    final List<ProcedureProfilePoint> points =
    await MainDatabaseHelper.db.findProcedureProfile(procedureName);
    if (loadId != _loadId) {
      return;
    }
    final List<_VerticalProfilePoint> profilePoints = points
        .map((point) => _VerticalProfilePoint(
      name: point.fixIdentifier,
      coordinate: point.coordinate,
      altitudeFt: point.altitudeFt,
    ))
        .toList();
    final LatLng? runway = await _findRunwayCoordinate(procedureName, profilePoints);
    _updateProfileDistances(profilePoints, runway);
    if (loadId != _loadId) {
      return;
    }
    _points
      ..clear()
      ..addAll(profilePoints);
  }

  Future<LatLng?> _findRunwayCoordinate(
      String procedureName,
      List<_VerticalProfilePoint> points,
      ) async {
    final RegExp runwayExp = RegExp(r'^RW\d+[LRC]?$');
    for (final point in points) {
      if (runwayExp.hasMatch(point.name)) {
        return point.coordinate;
      }
    }
    final List<String> segments = procedureName.split(".");
    if (segments.isEmpty) {
      return null;
    }
    final String airportId = segments[0].trim().toUpperCase();
    String runway = "";
    if (segments.length > 1) {
      runway = segments[1].toUpperCase().replaceAll(RegExp(r'[^0-9LRC]'), '');
      if (runway.isNotEmpty) {
        runway = _normalizeRunwayIdent(runway);
      }
    }
    if (runway.isEmpty) {
      return null;
    }
    final AirportDestination? airport = await MainDatabaseHelper.db.findAirport(airportId);
    if (airport == null) {
      return null;
    }
    return Airport.findCoordinatesFromRunway(airport, "RW$runway");
  }

  String _normalizeRunwayIdent(String runway) {
    final RegExp exp = RegExp(r'^(\d+)([LRC]?)$');
    final Match? match = exp.firstMatch(runway);
    if (match == null) {
      return runway;
    }
    String number = match.group(1) ?? runway;
    final String side = match.group(2) ?? "";
    if (number.length == 1) {
      number = "0$number";
    }
    return "$number$side";
  }

  void _updateProfileDistances(List<_VerticalProfilePoint> points, LatLng? runway) {
    if (points.isEmpty) {
      return;
    }
    double cumulative = 0;
    final List<double> distancesFromStart = List.filled(points.length, 0);
    distancesFromStart[0] = 0;
    points[0].distanceNm = 0;
    for (int index = 1; index < points.length; index++) {
      final double segmentNm =
          _profileDistance(points[index - 1].coordinate, points[index].coordinate) *
              _metersToNm;
      cumulative += segmentNm;
      distancesFromStart[index] = cumulative;
      points[index].distanceNm = cumulative;
    }
    if (runway == null) {
      return;
    }
    final double? runwayDistance = _distanceAlongPath(points, distancesFromStart, runway);
    if (runwayDistance == null) {
      return;
    }
    for (int index = 0; index < points.length; index++) {
      points[index].distanceNm = (distancesFromStart[index] - runwayDistance).abs();
    }
  }

  double? _distanceAlongPath(
      List<_VerticalProfilePoint> points,
      List<double> distancesFromStart,
      LatLng target,
      ) {
    if (points.length < 2) {
      return null;
    }
    double bestSq = double.infinity;
    double? bestDistance;
    for (int index = 0; index < points.length - 1; index++) {
      final LatLng a = points[index].coordinate;
      final LatLng b = points[index + 1].coordinate;
      final double refLat = GeoCalculations.toRadians((a.latitude + b.latitude) / 2);
      final Offset aNm = _toLocalNm(a, refLat);
      final Offset bNm = _toLocalNm(b, refLat);
      final Offset pNm = _toLocalNm(target, refLat);
      final Offset ab = bNm - aNm;
      final Offset ap = pNm - aNm;
      final double abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
      if (abLenSq == 0) {
        continue;
      }
      double t = (ap.dx * ab.dx + ap.dy * ab.dy) / abLenSq;
      t = t.clamp(0, 1).toDouble();
      final Offset proj = Offset(aNm.dx + ab.dx * t, aNm.dy + ab.dy * t);
      final Offset diff = pNm - proj;
      final double distSq = diff.dx * diff.dx + diff.dy * diff.dy;
      if (distSq < bestSq) {
        bestSq = distSq;
        final double segmentDistance = distancesFromStart[index + 1] - distancesFromStart[index];
        bestDistance = distancesFromStart[index] + segmentDistance * t;
      }
    }
    return bestDistance;
  }

  Offset _toLocalNm(LatLng point, double refLat) {
    const double earthRadiusNm = 3440.069;
    final double lat = GeoCalculations.toRadians(point.latitude);
    final double lon = GeoCalculations.toRadians(point.longitude);
    return Offset(
      lon * cos(refLat) * earthRadiusNm,
      lat * earthRadiusNm,
    );
  }
}

class _VerticalProfilePoint {
  final String name;
  final LatLng coordinate;
  final double? altitudeFt;
  double distanceNm = 0;
  _VerticalProfilePoint({
    required this.name,
    required this.coordinate,
    required this.altitudeFt,
  });
}

class _VerticalProfilePainter extends CustomPainter {
  static const double _earthRadiusNm = 3440.069;
  final List<_VerticalProfilePoint> points;
  final String label;
  final Color textColor;
  final Paint _axisPaint;
  final Paint _gridPaint;
  final Paint _linePaint;
  final Paint _pointPaint;
  final Paint _planePaint;

  _VerticalProfilePainter(
      ValueNotifier repaint,
      this.points, {
        required this.label,
        required this.textColor,
        required Color axisColor,
        required Color lineColor,
        required Color planeColor,
      }) :
        _axisPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = axisColor,
        _gridPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = axisColor.withValues(alpha: 0.3),
        _linePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = lineColor,
        _pointPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = lineColor,
        _planePaint = Paint()
          ..style = PaintingStyle.fill
          ..color = planeColor,
        super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    final List<_VerticalProfilePoint> altitudePoints =
    points.where((point) => point.altitudeFt != null).toList();
    final List<_VerticalProfilePoint> labelPoints = altitudePoints
        .where((point) => !_isMissedApproachPoint(point.name))
        .toList();
    if (altitudePoints.isEmpty) {
      return;
    }
    const double leftPad = 42;
    const double topPad = 20;
    const double rightPad = 12;
    const double bottomPad = 30;
    final Rect chart = Rect.fromLTRB(
      leftPad,
      topPad,
      size.width - rightPad,
      size.height - bottomPad,
    );
    if (chart.width <= 0 || chart.height <= 0) {
      return;
    }

    canvas.drawRect(chart, _axisPaint);
    _drawText(canvas, label, Offset(chart.left, 2), fontSize: 11, fontWeight: FontWeight.bold);

    double minAlt = altitudePoints
        .map((point) => point.altitudeFt!)
        .reduce(min);
    double maxAlt = altitudePoints
        .map((point) => point.altitudeFt!)
        .reduce(max);
    final double planeAlt = GeoCalculations.convertAltitude(Storage().position.altitude);
    minAlt = min(minAlt, planeAlt);
    maxAlt = max(maxAlt, planeAlt);
    if ((maxAlt - minAlt) < 500) {
      final double mid = (minAlt + maxAlt) / 2;
      minAlt = mid - 250;
      maxAlt = mid + 250;
    }
    final double padding = max(100, (maxAlt - minAlt) * 0.1);
    minAlt = max(0, minAlt - padding);
    maxAlt = maxAlt + padding;
    minAlt = (minAlt / 1000).floor() * 1000;
    maxAlt = (maxAlt / 1000).ceil() * 1000;
    if (maxAlt == minAlt) {
      maxAlt = minAlt + 1000;
    }

    double totalDistance = points
        .map((point) => point.distanceNm)
        .reduce(max);
    if (totalDistance <= 0) {
      totalDistance = 1;
    }

    for (double tick = minAlt; tick <= maxAlt; tick += 1000) {
      final double y = _yForAltitude(chart, tick, minAlt, maxAlt);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), _gridPaint);
      _drawText(
        canvas,
        "${tick.round()} ft",
        Offset(chart.left - 6, y - 5),
        align: TextAlign.right,
        fontSize: 8,
      );
    }

    _drawText(
      canvas,
      "${totalDistance.toStringAsFixed(1)} nm",
      Offset(chart.left, chart.bottom + 2),
    );
    _drawText(
      canvas,
      "0 nm",
      Offset(chart.right, chart.bottom + 2),
      align: TextAlign.right,
    );

    final ui.Path path = ui.Path();
    bool hasStarted = false;
    for (final point in points) {
      final double? altitude = point.altitudeFt;
      if (altitude == null) {
        hasStarted = false;
        continue;
      }
      final double x = _xForDistance(chart, point.distanceNm, totalDistance, fromLanding: true);
      final double y = _yForAltitude(chart, altitude, minAlt, maxAlt);
      if (!hasStarted) {
        path.moveTo(x, y);
        hasStarted = true;
      }
      else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, _linePaint);

    for (final point in points) {
      if (point.altitudeFt == null || _isMissedApproachPoint(point.name)) {
        continue;
      }
      final double x = _xForDistance(chart, point.distanceNm, totalDistance, fromLanding: true);
      final double y = _yForAltitude(chart, point.altitudeFt!, minAlt, maxAlt);
      canvas.drawCircle(Offset(x, y), 2.5, _pointPaint);
    }

    double lastLabelRight = -double.infinity;
    for (final point in labelPoints) {
      final double x = _xForDistance(chart, point.distanceNm, totalDistance, fromLanding: true);
      canvas.drawLine(
        Offset(x, chart.bottom),
        Offset(x, chart.bottom + 4),
        _axisPaint,
      );
      final String label = point.name;
      if (label.isEmpty) {
        continue;
      }
      final TextPainter measure = _measureText(label, fontSize: 9);
      final double clampedX = x
          .clamp(chart.left + measure.width / 2, chart.right - measure.width / 2)
          .toDouble();
      final double left = clampedX - measure.width / 2;
      final double right = clampedX + measure.width / 2;
      if (left <= lastLabelRight + 4) {
        continue;
      }
      _drawText(
        canvas,
        label,
        Offset(clampedX, chart.bottom + 14),
        align: TextAlign.center,
        fontSize: 9,
      );
      lastLabelRight = right;
    }

    final LatLng plane = Gps.toLatLng(Storage().position);
    final _VerticalProfilePoint? landingPoint = _landingPoint(points);
    double? planeDistance;
    if (landingPoint != null) {
      const Distance distanceCalculator = Distance(calculator: Haversine());
      planeDistance = distanceCalculator(plane, landingPoint.coordinate) * _metersToNm;
    }
    planeDistance ??= _closestDistanceAlongPath(points, plane);
    if (planeDistance != null) {
      final double clampedDistance = planeDistance.clamp(0, totalDistance).toDouble();
      final double x = _xForDistance(chart, clampedDistance, totalDistance, fromLanding: true);
      double y = _yForAltitude(chart, planeAlt, minAlt, maxAlt);
      y = y.clamp(chart.top, chart.bottom).toDouble();
      canvas.drawCircle(Offset(x, y), 3.5, _planePaint);
    }
  }

  double _xForDistance(Rect chart, double distance, double totalDistance, {bool fromLanding = false}) {
    final double frac = distance / totalDistance;
    return fromLanding
        ? chart.right - frac * chart.width
        : chart.left + frac * chart.width;
  }

  double _yForAltitude(Rect chart, double altitude, double minAlt, double maxAlt) {
    return chart.bottom - ((altitude - minAlt) / (maxAlt - minAlt)) * chart.height;
  }

  TextPainter _measureText(String text, {double fontSize = 10, FontWeight fontWeight = FontWeight.normal}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: fontSize, fontWeight: fontWeight),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    return tp;
  }

  void _drawText(
      Canvas canvas,
      String text,
      Offset position, {
        TextAlign align = TextAlign.left,
        double fontSize = 10,
        FontWeight fontWeight = FontWeight.normal,
      }) {
    final TextPainter tp = _measureText(text, fontSize: fontSize, fontWeight: fontWeight);
    Offset drawOffset = position;
    if (align == TextAlign.center) {
      drawOffset = Offset(position.dx - tp.width / 2, position.dy);
    }
    else if (align == TextAlign.right) {
      drawOffset = Offset(position.dx - tp.width, position.dy);
    }
    tp.paint(canvas, drawOffset);
  }

  bool _isMissedApproachPoint(String name) {
    return name.trim().toUpperCase() == "MAP";
  }

  double? _closestDistanceAlongPath(List<_VerticalProfilePoint> points, LatLng plane) {
    if (points.length < 2) {
      return null;
    }
    double bestSq = double.infinity;
    double? bestAlong;
    for (int index = 0; index < points.length - 1; index++) {
      final LatLng a = points[index].coordinate;
      final LatLng b = points[index + 1].coordinate;
      final double refLat = GeoCalculations.toRadians((a.latitude + b.latitude) / 2);
      final Offset aNm = _toLocalNm(a, refLat);
      final Offset bNm = _toLocalNm(b, refLat);
      final Offset pNm = _toLocalNm(plane, refLat);
      final Offset ab = bNm - aNm;
      final Offset ap = pNm - aNm;
      final double abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
      if (abLenSq == 0) {
        continue;
      }
      double t = (ap.dx * ab.dx + ap.dy * ab.dy) / abLenSq;
      t = t.clamp(0, 1).toDouble();
      final Offset proj = Offset(aNm.dx + ab.dx * t, aNm.dy + ab.dy * t);
      final Offset diff = pNm - proj;
      final double distSq = diff.dx * diff.dx + diff.dy * diff.dy;
      if (distSq < bestSq) {
        bestSq = distSq;
        final double segmentDistance = points[index + 1].distanceNm - points[index].distanceNm;
        bestAlong = points[index].distanceNm + segmentDistance * t;
      }
    }
    return bestAlong;
  }

  Offset _toLocalNm(LatLng point, double refLat) {
    final double lat = GeoCalculations.toRadians(point.latitude);
    final double lon = GeoCalculations.toRadians(point.longitude);
    return Offset(
      lon * cos(refLat) * _earthRadiusNm,
      lat * _earthRadiusNm,
    );
  }

  _VerticalProfilePoint? _landingPoint(List<_VerticalProfilePoint> points) {
    if (points.isEmpty) {
      return null;
    }
    _VerticalProfilePoint landing = points.first;
    for (final point in points.skip(1)) {
      if (point.distanceNm < landing.distanceNm) {
        landing = point;
      }
    }
    return landing;
  }

  @override
  bool shouldRepaint(_VerticalProfilePainter oldDelegate) => true;
}

class ProcedureProfilePoint {
  final String fixIdentifier;
  final LatLng coordinate;
  final double? altitudeFt;
  const ProcedureProfilePoint({
    required this.fixIdentifier,
    required this.coordinate,
    required this.altitudeFt,
  });
}