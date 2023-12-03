import 'package:flutter/material.dart';

// implements a drawing screen with a center reset button.

class DrawCanvas extends StatefulWidget {
  const DrawCanvas({super.key});
  @override
  State<StatefulWidget> createState() => DrawCanvasState();
}

class DrawCanvasState extends State<DrawCanvas> {
  @override
  Widget build(BuildContext context) {
    return
      Scaffold(
        body : Stack(
          children: [
            CustomPaint(painter: _MapPainter()),
            Positioned(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: IconButton(onPressed: () {  }, icon: const Icon(Icons.gps_fixed)),)),
              ),
          ]
        ),
      );
  }
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Define a paint object
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Colors.white;
    canvas.drawCircle(const Offset(100, 100), 10, paint);
  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) => false;
}

