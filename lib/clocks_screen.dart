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

