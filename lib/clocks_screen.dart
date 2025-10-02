import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'constants.dart';

class ClocksScreen extends StatefulWidget {
  const ClocksScreen({super.key});

  @override
  State<StatefulWidget> createState() => ClocksScreenState();
}

class ClocksScreenState extends State<ClocksScreen> {
  late Timer _ticker;

  final List<(String, String)> _zones = const [
    ("UTC", "UTC"),
    ("Los Angeles", "America/Los_Angeles"),
    ("New York", "America/New_York"),
    ("London", "Europe/London"),
    ("Paris", "Europe/Paris"),
    ("Moscow", "Europe/Moscow"),
    ("Dubai", "Asia/Dubai"),
    ("Delhi", "Asia/Kolkata"),
    ("Hong Kong", "Asia/Hong_Kong"),
    ("Tokyo", "Asia/Tokyo"),
    // ("Sydney", "Australia/Sydney"), // Keep to 10 total
  ];

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool portrait = Constants.isPortrait(context);
    int crossAxisCount = portrait ? 2 : 4;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Clocks"),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1,
        ),
        itemCount: _zones.length,
        itemBuilder: (_, index) {
          final (city, zone) = _zones[index];
          final tz.TZDateTime now = tz.TZDateTime.now(tz.getLocation(zone));
          return _ClockTile(city: city, now: now);
        },
      ),
    );
  }
}

class _ClockTile extends StatelessWidget {
  final String city;
  final DateTime now;
  const _ClockTile({required this.city, required this.now});

  @override
  Widget build(BuildContext context) {
    Color dialColor = Theme.of(context).cardColor.withValues(alpha: 0.8);
    Color handColor = Theme.of(context).colorScheme.primary;
    Color secondHandColor = Theme.of(context).colorScheme.secondary;
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        color: dialColor,
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double size = min(constraints.maxWidth, constraints.maxHeight);
                  return CustomPaint(
                    size: Size.square(size),
                    painter: _AnalogClockPainter(
                      now: now,
                      dialColor: Theme.of(context).scaffoldBackgroundColor,
                      tickColor: Theme.of(context).hintColor,
                      handColor: handColor,
                      secondHandColor: secondHandColor,
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              children: [
                Text(city, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(_format(now), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _format(DateTime t) {
    String hh = t.hour.toString().padLeft(2, '0');
    String mm = t.minute.toString().padLeft(2, '0');
    String ss = t.second.toString().padLeft(2, '0');
    return "$hh:$mm:$ss";
  }
}

class _AnalogClockPainter extends CustomPainter {
  final DateTime now;
  final Color dialColor;
  final Color tickColor;
  final Color handColor;
  final Color secondHandColor;

  _AnalogClockPainter({
    required this.now,
    required this.dialColor,
    required this.tickColor,
    required this.handColor,
    required this.secondHandColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = min(size.width, size.height) / 2;

    final Paint facePaint = Paint()
      ..color = dialColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, facePaint);

    final Paint borderPaint = Paint()
      ..color = tickColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);

    final Paint tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final Paint hourTickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 60; i++) {
      final double tickLength = (i % 5 == 0) ? radius * 0.10 : radius * 0.05;
      final Paint p = (i % 5 == 0) ? hourTickPaint : tickPaint;
      final double angle = (pi / 30) * i;
      final double outerX = center.dx + (radius - 6) * sin(angle);
      final double outerY = center.dy - (radius - 6) * cos(angle);
      final double innerX = center.dx + (radius - 6 - tickLength) * sin(angle);
      final double innerY = center.dy - (radius - 6 - tickLength) * cos(angle);
      canvas.drawLine(Offset(innerX, innerY), Offset(outerX, outerY), p);
    }

    final int hour = now.hour % 12;
    final int minute = now.minute;
    final int second = now.second;

    final double hourAngle = (pi / 6) * (hour + minute / 60 + second / 3600);
    final double minuteAngle = (pi / 30) * (minute + second / 60);
    final double secondAngle = (pi / 30) * second;

    final Paint hourHandPaint = Paint()
      ..color = handColor
      ..strokeWidth = radius * 0.06
      ..strokeCap = StrokeCap.round;
    final Paint minuteHandPaint = Paint()
      ..color = handColor
      ..strokeWidth = radius * 0.04
      ..strokeCap = StrokeCap.round;
    final Paint secondHandPaint = Paint()
      ..color = secondHandColor
      ..strokeWidth = radius * 0.02
      ..strokeCap = StrokeCap.round;

    _drawHand(canvas, center, radius * 0.55, hourAngle, hourHandPaint);
    _drawHand(canvas, center, radius * 0.75, minuteAngle, minuteHandPaint);
    _drawHand(canvas, center, radius * 0.85, secondAngle, secondHandPaint);

    final Paint centerDot = Paint()..color = handColor;
    canvas.drawCircle(center, radius * 0.04, centerDot);
  }

  void _drawHand(Canvas canvas, Offset center, double length, double angle, Paint paint) {
    final double x = center.dx + length * sin(angle);
    final double y = center.dy - length * cos(angle);
    canvas.drawLine(center, Offset(x, y), paint);
  }

  @override
  bool shouldRepaint(covariant _AnalogClockPainter oldDelegate) {
    return oldDelegate.now.second != now.second ||
        oldDelegate.dialColor != dialColor ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.handColor != handColor ||
        oldDelegate.secondHandColor != secondHandColor;
  }
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ClocksScreen extends StatefulWidget {
  const ClocksScreen({super.key});

  @override
  State<ClocksScreen> createState() => _ClocksScreenState();
}

class _ClocksScreenState extends State<ClocksScreen> {
  late Timer _timer;

  final List<_CityTz> _cities = const [
    _CityTz('Los Angeles', -7), // PDT
    _CityTz('New York', -4), // EDT
    _CityTz('UTC', 0),
    _CityTz('London', 1), // BST
    _CityTz('Paris', 2), // CEST
    _CityTz('Dubai', 4), // GST
    _CityTz('Mumbai', 5.5), // IST
    _CityTz('Singapore', 8), // SGT
    _CityTz('Tokyo', 9), // JST
    _CityTz('Sydney', 10), // AEST
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('World Clocks')),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1,
        ),
        itemCount: _cities.length,
        itemBuilder: (context, index) {
          final city = _cities[index];
          final nowUtc = DateTime.now().toUtc();
          final now = nowUtc.add(Duration(
              hours: city.offsetHours.floor(),
              minutes: ((city.offsetHours - city.offsetHours.floor()) * 60).round()));
          final timeText = DateFormat('EEE, MMM d\nHH:mm:ss').format(now);
          return Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: CustomPaint(
                          painter: _AnalogClockPainter(now),
                          isComplex: true,
                          willChange: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(city.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(timeText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CityTz {
  final String name;
  final double offsetHours; // relative to UTC
  const _CityTz(this.name, this.offsetHours);
}

class _AnalogClockPainter extends CustomPainter {
  final DateTime now;
  _AnalogClockPainter(this.now);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 6;

    final facePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, facePaint);

    final borderPaint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);

    // hour ticks
    final tickPaint = Paint()
      ..color = Colors.grey.shade700
      ..strokeWidth = 2;
    for (int i = 0; i < 60; i++) {
      final isHour = i % 5 == 0;
      final length = isHour ? 10.0 : 5.0;
      final angle = 2 * pi * (i / 60);
      final p1 = center + Offset(cos(angle), sin(angle)) * (radius - length);
      final p2 = center + Offset(cos(angle), sin(angle)) * radius;
      canvas.drawLine(p1, p2, tickPaint..strokeWidth = isHour ? 2 : 1);
    }

    // hands
    final hours = now.hour % 12 + now.minute / 60 + now.second / 3600;
    final minutes = now.minute + now.second / 60;
    final seconds = now.second + now.millisecond / 1000;

    _drawHand(canvas, center, radius * 0.55, hours / 12 * 2 * pi, 4, Colors.black87);
    _drawHand(canvas, center, radius * 0.75, minutes / 60 * 2 * pi, 3, Colors.black87);
    _drawHand(canvas, center, radius * 0.85, seconds / 60 * 2 * pi, 1.5, Colors.redAccent);

    // center dot
    final centerDot = Paint()..color = Colors.black87;
    canvas.drawCircle(center, 3, centerDot);
  }

  void _drawHand(Canvas canvas, Offset center, double length, double angle, double width, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final end = center + Offset(cos(angle - pi / 2), sin(angle - pi / 2)) * length;
    canvas.drawLine(center, end, paint);
  }

  @override
  bool shouldRepaint(covariant _AnalogClockPainter oldDelegate) {
    return oldDelegate.now.second != now.second;
  }
}

