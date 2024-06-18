import 'package:flutter/material.dart';
import 'dart:math';

class TimeSegmentPieChart extends StatelessWidget {
  final List<DateTime> timeSegments;
  final List<Color> colors;

  const TimeSegmentPieChart({super.key, required this.timeSegments, required this.colors});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PieChartPainter(timeSegments, colors),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<DateTime> timeSegments;
  final List<Color> colors;

  _PieChartPainter(this.timeSegments, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    const totalDuration = Duration(hours: 12);

    double startAngle = -pi / 2;
    for(int i = 0; i < timeSegments.length - 1; i++) {
      Duration duration = timeSegments[i + 1].difference(timeSegments[i]);
      final sweepAngle = 2 * pi * duration.inSeconds / totalDuration.inSeconds;

      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.fill;

      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}


