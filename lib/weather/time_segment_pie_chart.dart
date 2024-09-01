import 'dart:math';

import 'package:flutter/material.dart';

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
  List<DateTimeColorPair> hourlyPairs = [];

  _PieChartPainter(this.timeSegments, this.colors) {
    List<DateTimeColorPair> pairs = List.generate(timeSegments.length, (index) => DateTimeColorPair(timeSegments[index], colors[index]));
    hourlyPairs = DateTimeColorPair.generateHourlySpacedList(pairs);
  }

  @override
  void paint(Canvas canvas, Size size) {

    if(hourlyPairs.isEmpty) {
      return;
    }
    double offset = 0;

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..strokeWidth = 3;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.height / 2, paint);
    double sizeDraw = size.height - 3;

    double lastAngle = -90;
    for(int i = 0; i < hourlyPairs.length - 1; i++) {

      final paint = Paint()
        ..color = hourlyPairs[i].color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      // include hours, days, months, and year
      double hours = hourlyPairs[i].dateTime.hour + hourlyPairs[i].dateTime.day * 24 + hourlyPairs[i].dateTime.month * 24 * 30 + hourlyPairs[i].dateTime.year * 24 * 30 * 12;

      // drawArc draws clockwise with 0 degree as in math, but clock's 0 degree is at -90 degree in math
      double angleStart = (hours % 12) / 12 * 360 - 90;
      double angleEnd = angleStart + 30; // each hour in 12 hour clock is 30 degree
      if(angleStart == -90 && lastAngle == 240) {
        // draw inner circle
        offset++;
      }
      if(offset > 2) { // this should draw 3 circles and cover 3 * 12 hours
        return;
      }
      lastAngle = angleStart;

      canvas.drawArc(Rect.fromLTRB(offset * 4 + 3, offset * 4 + 3, sizeDraw - offset * 4, sizeDraw - offset * 4), angleStart * pi / 180, (angleEnd - angleStart) * pi / 180, false, paint);
    }

    // draw a line from center to the edge that represents the current time in zulu
    DateTime now = DateTime.now().toUtc();
    double hours = now.hour + now.day * 24 + now.month * 24 * 30 + now.year * 24 * 30 * 12;
    double angle = (hours % 12) / 12 * 360 - 90;
    paint.color = Colors.black;
    paint.strokeWidth = 1;
    canvas.drawLine(Offset(size.width / 2, size.height / 2), Offset(size.width / 2 + size.height / 2 * cos(angle * pi / 180), size.height / 2 + size.height / 2 * sin(angle * pi / 180)), paint);

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}


class DateTimeColorPair {
  final DateTime dateTime;
  final Color color; // Replace with your actual color type

  DateTimeColorPair(this.dateTime, this.color);

  static List<DateTimeColorPair> generateHourlySpacedList(List<DateTimeColorPair> sortedList) {
    final List<DateTimeColorPair> result = [];

    if (sortedList.isEmpty) {
      return result;
    }

    // Initialize with the first value from the sorted list
    result.add(sortedList.first);

    // Calculate the hourly difference
    const Duration hourlyDuration = Duration(hours: 1);

    for (int i = 1; i < sortedList.length; i++) {
      final DateTimeColorPair prevPair = sortedList[i - 1];
      final DateTimeColorPair currentPair = sortedList[i];

      // Calculate the number of hours between the previous and current DateTime
      final int hourDiff = currentPair.dateTime.difference(prevPair.dateTime).inHours;

      // Add intermediate DateTime values spaced every hour
      for (int j = 1; j < hourDiff; j++) {
        final DateTime interpolatedDateTime = prevPair.dateTime.add(hourlyDuration * j).toLocal();
        result.add(DateTimeColorPair(interpolatedDateTime, prevPair.color));
      }

      // Add the current DateTime value
      result.add(currentPair);
    }

    return result;
  }

}


