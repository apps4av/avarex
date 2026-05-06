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

    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double rOuter = size.height / 2 - 1; // 1px margin so the outer stroke isn't clipped
    final double rInner = max(2.0, size.height / 8); // small core so the spiral doesn't collapse to a point

    // White background disc so the spiral reads against any map tile underneath.
    final bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), rOuter, bgPaint);

    // Number of hour segments to draw (the last entry in hourlyPairs is the
    // validity-end marker, with no segment of its own — same convention as
    // before). Cap at 36 so the spiral stays readable on small icons.
    final int totalHours = hourlyPairs.length - 1;
    if (totalHours <= 0) {
      return;
    }
    final int hoursToDraw = totalHours > 36 ? 36 : totalHours;

    // Sizing: one full 12-hour turn shrinks the spiral inward by `radialPerTurn`,
    // and we draw each turn with a stroke narrower than that by `gapFraction`
    // so a thin white band shows between successive turns. The whole spiral
    // still fills the [rInner, rOuter] band exactly: segment 0's outer edge
    // sits on rOuter and segment N-1's inner edge sits on rInner.
    //
    //   sw             = (1 - g) * radialPerTurn
    //   r_i            = rOuter - sw/2 - (i/12) * radialPerTurn
    //   r_{N-1} - sw/2 = rInner
    //     ⇒  radialPerTurn = (rOuter - rInner) * 12 / (N + 11 - 12g)
    const double gapFraction = 0.25;
    final double radialPerTurn = (rOuter - rInner) * 12.0 /
        (hoursToDraw + 11.0 - 12.0 * gapFraction);
    final double sw = radialPerTurn * (1.0 - gapFraction);

    // Anchor the spiral so segments still align with clock-hour positions
    // (12 at top, 3 at right, etc.), the same as the previous concentric
    // design. The first segment starts at its own clock angle; subsequent
    // segments advance by 30° (1 hour) and shrink radially.
    final DateTime firstDt = hourlyPairs[0].dateTime.toUtc();
    final double firstClockHour = firstDt.hour + firstDt.minute / 60.0;

    for (int i = 0; i < hoursToDraw; i++) {
      final segPaint = Paint()
        ..color = hourlyPairs[i].color
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw;

      final double r = rOuter - sw / 2 - (i / 12.0) * radialPerTurn;
      if (r <= 0) break;

      final double clockHour = firstClockHour + i.toDouble();
      final double angleDeg = ((clockHour % 12) / 12.0) * 360.0 - 90.0;

      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        angleDeg * pi / 180.0,
        30.0 * pi / 180.0, // each hour is 30° on a 12-hour clock face
        false,
        segPaint,
      );
    }

    // "Now" hand — black radial line from center to outer edge at the current
    // UTC clock-face angle. Crosses every loop of the spiral so the user can
    // see at a glance which segments are in the past vs. the future.
    final DateTime now = DateTime.now().toUtc();
    final double nowAngle = (((now.hour + now.minute / 60.0) % 12) / 12.0) * 360.0 - 90.0;
    final handPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + rOuter * cos(nowAngle * pi / 180.0),
             cy + rOuter * sin(nowAngle * pi / 180.0)),
      handPaint,
    );
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

      // Add intermediate DateTime values spaced every hour. Keep them in
      // UTC so the painter (which reads .hour in UTC) renders consistently.
      for (int j = 1; j < hourDiff; j++) {
        final DateTime interpolatedDateTime = prevPair.dateTime.add(hourlyDuration * j).toUtc();
        result.add(DateTimeColorPair(interpolatedDateTime, prevPair.color));
      }

      // Add the current DateTime value
      result.add(currentPair);
    }

    return result;
  }

}


