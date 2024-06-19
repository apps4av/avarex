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

    double fac = size.width / hourlyPairs.length;

    for(int i = 0; i < hourlyPairs.length - 1; i++) {

      final paint = Paint()
        ..color = hourlyPairs[i].color
        ..style = PaintingStyle.fill
        ..strokeWidth = 8.0;

      canvas.drawLine(Offset(i * fac, size.height / 2), Offset((i + 1) * fac, size.height / 2), paint);
    }
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
      for (int j = 1; j <= hourDiff; j++) {
        final DateTime interpolatedDateTime = prevPair.dateTime.add(hourlyDuration * j);
        result.add(DateTimeColorPair(interpolatedDateTime, prevPair.color));
      }

      // Add the current DateTime value
      result.add(currentPair);
    }

    return result;
  }

}


