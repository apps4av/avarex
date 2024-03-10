import 'dart:math';

import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

class PfdPainter extends CustomPainter {


  PfdPainter({required ValueNotifier repaint, required height, required width}) : super(repaint: repaint) {
    _height = height;
    _width = width;
  }

  double _height = 0;
  double _width = 0;

  TextPainter paintText = TextPainter()
     ..textAlign = TextAlign.left
     ..textDirection = TextDirection.ltr;

  Paint paintFill = Paint()
    ..style = PaintingStyle.fill;

  Paint paintStroke = Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.white
    ..strokeWidth = 1.5;

  static const double speedTen = 1.5;
  static const double altitudeThousand = 1.5;
  static const double vsiFive = 1.5;
  static const double pitchDegree = 4;
  static const double vdiDegree = 30;

  static const double vnavBarDegree = 0.14;
  static const double vnavApproachDistance = 15;

  static const double vnavHigh = 3.7;
  static const double vnavLow = 2.3;

  /// PAn the whole drawing up with this fraction of screen to utilize maximum screen
  static const double yPan = 0.125;

  /// Xform 0,0 in center, and (100, 100) on top right, and (-100, -100) on bottom left
  /// @param yval
  /// @return
  double _y(double yval) {
    double yPercent = _height / 200;
    return _height / 2 - yval * yPercent - _height * yPan;
  }

  /// Xform 0,0 in center, and (100, 100) on top right, and (-100, -100) on bottom left
  /// @param xval
  /// @return
  double _x(double xval) {
    double xPercent = _width / 200;
    return _width / 2 + xval * xPercent;
  }


  @override
  void paint(Canvas canvas, Size size) {

    void rotate(double angle, double cx, double cy) {
      canvas.translate(cx, cy);
      canvas.rotate(angle * pi / 180);
      canvas.translate(-cx, -cy);
    }

    void drawLine(double x0, double y0, double x1, double y1, Paint paint) {
      canvas.drawLine(Offset(x0, y0), Offset(x1, y1), paint);
    }

    void drawCircle(double x0, double y0, double r, Paint paint) {
      canvas.drawCircle(Offset(x0, y0), r, paint);
    }

    void drawRect(double x0, double y0, double x1, double y1, Paint paint) {
      canvas.drawRect(Rect.fromLTRB(x0, y0, x1, y1), paint);
    }

    void drawText(String value, double x, double y) {
      TextSpan span = TextSpan(text: value, style: TextStyle(fontSize: _height / 40));
      paintText.text = span;
      paintText.layout();
      paintText.paint(canvas, Offset(x, y - paintText.height / 2));
    }

    PfdData pfd = Storage().pfdData;

    /*
     * draw pitch / roll
     */
    canvas.save();


    rotate(pfd.roll, _x(0), _y(0));
    canvas.translate(0, _y(0) - _y(pfd.pitch * pitchDegree));

    paintFill.color = const Color(0xFF0000A0);
    drawRect(_x(-400), _y(pitchDegree * 90), _x(400), _y(0), paintFill);

    paintFill.color = const Color(0xFF624624);
    drawRect(_x(-400), _y(0), _x(400), _y(-pitchDegree * 90), paintFill);

    //center attitude degrees
    drawLine(_x(-150), _y(0), _x(150), _y(0), paintStroke);

    // degree lines
    double degrees = (((pfd.pitch + 1.25) / 2.5).round().toDouble() * 2.5);

    for(double d = -12.5; d <= 12.5; d += 2.5) {
      double inc = degrees + d;
      if (0 == inc % 10) {
        drawLine(_x(-12), _y(inc * pitchDegree), _x(12), _y(inc * pitchDegree), paintStroke);
        if(0 == inc) {
          continue;
        }
        drawText("${inc.abs().round()}", _x(12), _y(inc * pitchDegree));
      }
      if (0 == inc % 5) {
        drawLine(_x(-4), _y(inc * pitchDegree), _x(4), _y(inc * pitchDegree), paintStroke);
      }
      else {
        drawLine(_x(-2), _y(inc * pitchDegree), _x(2), _y(inc * pitchDegree), paintStroke);
      }
    }

    canvas.restore();


    /*
     * draw AOA
     */
    canvas.save();

    Color c1, c2, c3, c4, c5, c6, c7, c8, c9;

    c1 = Colors.grey;
    c2 = Colors.grey;
    c3 = Colors.grey;
    c4 = Colors.grey;
    c5 = Colors.grey;
    c6 = Colors.grey;
    c7 = Colors.grey;
    c8 = Colors.grey;
    c9 = Colors.grey;

    if(pfd.aoa > (1 - 1/6)) {
      c9 = Colors.red;
    }
    if(pfd.aoa > (1 - 2/6)) {
      c8 = Colors.red;
    }
    if (pfd.aoa > (1 - 2.5/6)) {
      c7 = Colors.yellow;
    }
    if (pfd.aoa > (1 - 3/6)) {
      c6 = Colors.yellow;
    }
    if (pfd.aoa > (1 - 3.5/6)) {
      c5 = Colors.yellow;
    }
    if (pfd.aoa > (1 - 4/6)) {
      c4 = Colors.yellow;
    }
    if (pfd.aoa > (1 - 4.5/6)) {
      c3 = Colors.green;
    }
    if (pfd.aoa > (1 - 5.0/6)) {
      c2 = Colors.green;
    }
    if (pfd.aoa >= (0)) {
      c1 = Colors.green;
    }

    paintFill.color = Colors.black;
    Path path = Path();
    path.reset();
    path.moveTo(_x(-45) , _y(31));
    path.lineTo(_x(-45), _y(5));
    path.lineTo(_x(-25), _y(5));
    path.lineTo(_x(-25), _y(31));

    canvas.drawPath(path, paintFill);

    paintStroke.color = c1;
    drawLine(_x(-44), _y(6), _x(-26), _y(6), paintStroke);

    paintStroke.color = c2;
    drawLine(_x(-44), _y(9), _x(-26), _y(9), paintStroke);

    paintStroke.color = c3;
    drawLine(_x(-44), _y(12), _x(-38), _y(12), paintStroke);
    drawLine(_x(-32), _y(12), _x(-26), _y(12), paintStroke);
    drawCircle(_x(-35), _y(12), 4, paintStroke);

    paintStroke.color = c4;
    drawLine(_x(-44), _y(15), _x(-26), _y(15), paintStroke);

    paintStroke.color = c5;
    drawLine(_x(-44), _y(18), _x(-38), _y(18), paintStroke);
    drawLine(_x(-32), _y(18), _x(-26), _y(18), paintStroke);

    //chevrons
    paintStroke.color = c6;
    drawLine(_x(-44), _y(21), _x(-35), _y(18), paintStroke);
    drawLine(_x(-35), _y(18), _x(-26), _y(21), paintStroke);

    paintStroke.color = c7;
    drawLine(_x(-44), _y(24), _x(-35), _y(21), paintStroke);
    drawLine(_x(-35), _y(21), _x(-26), _y(24), paintStroke);

    paintStroke.color = c8;
    drawLine(_x(-44), _y(27), _x(-35), _y(24), paintStroke);
    drawLine(_x(-35), _y(24), _x(-26), _y(27), paintStroke);

    paintStroke.color = c9;
    drawLine(_x(-44), _y(30), _x(-35), _y(27), paintStroke);
    drawLine(_x(-35), _y(27), _x(-26), _y(30), paintStroke);

    canvas.restore();


    canvas.save();

    rotate(pfd.roll, _x(0), _y(0));

    //draw roll arc
    paintFill.color = Colors.white;
    paintStroke.color = Colors.white;
    double r = _y(0) - _y(70);
    Rect rect = Rect.fromLTRB(_x(0) - r, _y(0) - r, _x(0) + r, _y(0) + r);
    canvas.drawArc(rect, 210 * pi / 180, 120 * pi / 180, false, paintStroke);

    // degree ticks
    //60
    rotate(-60, _x(0), _y(0));
    drawLine(_x(0), _y(75), _x(0), _y(70), paintStroke);

    //45
    rotate(15, _x(0), _y(0));
    drawLine(_x(0), _y(73), _x(0), _y(70), paintStroke);

    //30
    rotate(15, _x(0), _y(0));
    drawLine(_x(0), _y(75), _x(0), _y(70), paintStroke);

    //20
    rotate(10, _x(0), _y(0));
    drawLine(_x(0), _y(73), _x(0), _y(70), paintStroke);

    //10
    rotate(10, _x(0), _y(0));
    drawLine(_x(0), _y(73), _x(0), _y(70), paintStroke);


    // center arrow
    rotate(10, _x(0), _y(0));
    path.reset();
    path.moveTo(_x(-7), _y(75));
    path.lineTo(_x(0), _y(70));
    path.lineTo(_x(7), _y(75));
    canvas.drawPath(path, paintFill);

    //10
    rotate(10, _x(0), _y(0));
    drawLine(_x(0), _y(73), _x(0), _y(70), paintStroke);

    //20
    rotate(10, _x(0), _y(0));
    drawLine(_x(0), _y(73), _x(0), _y(70), paintStroke);

    //30
    rotate(10, _x(0), _y(0));
    drawLine(_x(0), _y(75), _x(0), _y(70), paintStroke);

    //45
    rotate(15, _x(0), _y(0));
    drawLine(_x(0), _y(73), _x(0), _y(70), paintStroke);

    //60
    rotate(15, _x(0), _y(0));
    drawLine(_x(0), _y(75), _x(0), _y(70), paintStroke);

    rotate(-60, _x(0), _y(0));


    canvas.restore();

    //bank arrow
    path.reset();
    path.moveTo(_x(7), _y(65));
    path.lineTo(_x(0), _y(70));
    path.lineTo(_x(-7), _y(65));
    canvas.drawPath(path, paintFill);

    // inclinometer, displace +-20 of screen from +- 10 degrees
    drawRect(_x(-7 + pfd.slip * 2), _y(64), _x(7 + pfd.slip * 2), _y(62), paintFill);


    // draw airplane wings
    paintFill.color = Colors.yellow;
    drawRect(_x(-45), _y(1), _x(-20), _y(-1), paintFill);
    drawRect(_x(20), _y(1), _x(45), _y(-1), paintFill);

    // draw airplane triangle
    path.reset();
    path.moveTo(_x(0) , _y(0));
    path.lineTo(_x(-15), _y(-10));
    path.lineTo(_x(0), _y(-5));
    path.lineTo(_x(15), _y(-10));
    canvas.drawPath(path, paintFill);

    /**
     * Speed tape
     */
    paintStroke.color = Colors.white;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(_x(-80), _y(35), _x(-50), _y(-35)));
    canvas.translate(0, _y(0) - _y(pfd.speed * speedTen));

    // lines, just draw + - 30
    double tens = (pfd.speed / 10).round() * 10;
    for(double c = tens - 30; c <= tens + 30; c += 10) {
      if(c < 0) {
        continue; // no negative speed
      }
      drawLine(_x(-50), _y(c * speedTen), _x(-55), _y(c * speedTen), paintStroke);
      drawText("${c.abs().round()}", _x(-75), _y(c * speedTen));

    }
    for(double c = tens - 30; c <= tens + 30; c += 5) {
      if(c < 0) {
        continue; // no negative speed
      }
      drawLine(_x(-50), _y(c * speedTen), _x(-53), _y(c * speedTen), paintStroke);
    }

    canvas.restore();

    // trend
    paintFill.color = Colors.purpleAccent;
    if(pfd.speedChange > 0) {
      drawRect(_x(-53), _y(pfd.speedChange * speedTen), _x(-50), _y(0), paintFill);
    }
    else {
      drawRect(_x(-53), _y(0), _x(-50), _y(pfd.speedChange * speedTen), paintFill);
    }

    // value
    paintFill.color = Colors.black;

    path.reset();
    path.moveTo(_x(-80), _y(3));
    path.lineTo(_x(-55), _y(3));
    path.lineTo(_x(-50), _y(0));
    path.lineTo(_x(-55), _y(-3));
    path.lineTo(_x(-80), _y(-3));
    canvas.drawPath(path, paintFill);

    drawText("${pfd.speed.abs().round()}", _x(-75), _y(0));
    // boundary
    paintStroke.color = Colors.white;
    drawRect(_x(-80), _y(35), _x(-50), _y(-35), paintStroke);


    /**
     * Altitude tape
     */
    paintStroke.color = Colors.white;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(_x(35), _y(35), _x(85), _y(-35)));
    canvas.translate(0, _y(0) - _y(pfd.altitude * altitudeThousand / 10)); // alt is dealt in 10's of feet

    // lines, just draw + and - 300 ft.
    double hundreds = (pfd.altitude / 100).round() * 100;
    for(double c = (hundreds - 300) / 10; c <= (hundreds + 300) / 10; c += 10) {
      drawLine(_x(50), _y(c * altitudeThousand), _x(55), _y(c * altitudeThousand), paintStroke);

      drawText("${c.round()}0", _x(55), _y(c * altitudeThousand));
    }
    for(double c = (hundreds - 300) / 10; c <= (hundreds + 300) / 10; c += 2) {
      drawLine(_x(50), _y(c * altitudeThousand), _x(53), _y(c * altitudeThousand), paintStroke);
    }
    canvas.restore();

    // trend
    paintFill.color = Colors.purpleAccent;
    if(pfd.altitudeChange > 0) {
      drawRect(_x(50), _y(pfd.altitudeChange * altitudeThousand / 10), _x(52), _y(0), paintFill);
    }
    else {
      drawRect(_x(50), _y(0), _x(52), _y(pfd.altitudeChange * altitudeThousand / 10), paintFill);
    }

    // value
    paintFill.color = Colors.black;

    path.reset();
    path.moveTo(_x(50), _y(0));
    path.lineTo(_x(55), _y(3));
    path.lineTo(_x(85), _y(3));
    path.lineTo(_x(85), _y(-3));
    path.lineTo(_x(55), _y(-3));
    canvas.drawPath(path, paintFill);

    drawText("${pfd.altitude.round()}", _x(55), _y(0));

    // boundary
    paintStroke.color = Colors.white;
    drawRect(_x(50), _y(35), _x(85), _y(-35), paintStroke);

    /**
     * VSI tape
     */

    paintStroke.color = Colors.white;

    //lines
    drawLine(_x(90), _y(5   * vsiFive), _x(85), _y(5   * vsiFive), paintStroke);
    drawLine(_x(95), _y(10  * vsiFive), _x(85), _y(10  * vsiFive), paintStroke);
    drawLine(_x(90), _y(15  * vsiFive), _x(85), _y(15  * vsiFive), paintStroke);
    drawLine(_x(90), _y(-5  * vsiFive), _x(85), _y(-5  * vsiFive), paintStroke);
    drawLine(_x(95), _y(-10 * vsiFive), _x(85), _y(-10 * vsiFive), paintStroke);
    drawLine(_x(90), _y(-15 * vsiFive), _x(85), _y(-15 * vsiFive), paintStroke);


    // boundary
    path.reset();
    path.moveTo(_x(85), _y(20 * vsiFive));
    path.lineTo(_x(98), _y(20 * vsiFive));
    path.lineTo(_x(98), _y(5 * vsiFive));
    path.lineTo(_x(85), _y(0 * vsiFive));
    path.lineTo(_x(98), _y(-5 * vsiFive));
    path.lineTo(_x(98), _y(-20 * vsiFive));
    path.lineTo(_x(85), _y(-20 * vsiFive));
    canvas.drawPath(path, paintStroke);


    // text on VSI
    drawText("1", _x(90), _y(12 * vsiFive));
    drawText("2", _x(90), _y(22 * vsiFive));
    drawText("1", _x(90), _y(-8 * vsiFive));
    drawText("2", _x(90), _y(-18 * vsiFive));


    // value
    paintFill.color = Colors.black;

    double offs = pfd.vsi / 100 * vsiFive;
    path.reset();
    path.moveTo(_x(85), _y(0 * vsiFive + offs));
    path.lineTo(_x(92), _y(2.5 * vsiFive + offs));
    path.lineTo(_x(98), _y(2.5 * vsiFive + offs));
    path.lineTo(_x(98), _y(-2.5 * vsiFive + offs));
    path.lineTo(_x(92), _y(-2.5 * vsiFive + offs));
    path.lineTo(_x(85), _y(0 * vsiFive + offs));
    canvas.drawPath(path, paintFill);

    paintStroke.color = Colors.white;
    canvas.drawPath(path, paintStroke);

    // VSI hundreds
    int hvsi = ((pfd.vsi.abs()) % 1000) ~/ 100;
    drawText(hvsi.toString(), _x(90), _y(0 * vsiFive + offs));


    /**
     * Compass
     */

    // arrow
    paintFill.color = Colors.white;
    path.reset();
    path.moveTo(_x(-5), _y(-60));
    path.lineTo(_x(0), _y(-65));
    path.lineTo(_x(5), _y(-60));
    canvas.drawPath(path, paintFill);

    canvas.save();

    // half standrad rate, 9 degrees in 6 seconds
    rotate(-18, _x(0), _y(-95));
    drawLine(_x(0), _y(-60), _x(0), _y(-65), paintStroke);

    // standrad rate, 18 degrees in 6 seconds
    rotate(9, _x(0), _y(-95));
    drawLine(_x(0), _y(-60), _x(0), _y(-65), paintStroke);

    // standrad rate, 18 degrees in 6 seconds
    rotate(18, _x(0), _y(-95));
    drawLine(_x(0), _y(-60), _x(0), _y(-65), paintStroke);

    // half standrad rate, 9 degrees in 6 seconds
    rotate(9, _x(0), _y(-95));
    drawLine(_x(0), _y(-60), _x(0), _y(-65), paintStroke);

    canvas.restore();

    //draw 12, 30 degree marks.
    canvas.save();

    rotate(-pfd.yaw, _x(0), _y(-95));

    double offset = -paintText.width / 2;

    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("N", _x(0) + offset, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("3", _x(0) + offset, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("6", _x(0) + offset, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("E", _x(0) + offset, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("12", _x(0) + offset * 2, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("15", _x(0) + offset * 2, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("S", _x(0) + offset, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("21", _x(0) + offset * 2, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("24", _x(0) + offset * 2, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("W", _x(0) + offset, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("30", _x(0) + offset * 2, _y(-75));
    rotate(30, _x(0), _y(-95));
    drawLine(_x(0), _y(-65), _x(0), _y(-70), paintStroke);
    drawText("33", _x(0) + offset * 2, _y(-75));
    rotate(30, _x(0), _y(-95));

    canvas.restore();

    // airplane
    paintStroke.color = Colors.white;
    drawLine(_x(0), _y(-105), _x(0), _y(-85), paintStroke);

    //draw heading
    paintFill.color = Colors.black;
    drawRect(_x(-13), _y(-50), _x(13), _y(-58), paintFill);
    drawRect(_x(-13), _y(-50), _x(13), _y(-58), paintStroke);
    drawText("${((pfd.yaw + 360) % 360).round()}\u00B0", _x(-10), _y(-54),);

    // draw rate of turn arc.
    paintStroke.strokeWidth = 4;
    paintStroke.color = Colors.purpleAccent;
    r = _y(-95) - _y(-65);

    rect = Rect.fromLTRB(_x(0) - r, _y(-95) - r, _x(0) + r, _y(-95) + r);
    canvas.drawArc(rect, -90 * pi / 180, pfd.turnTrend * pi / 180, false, paintStroke);

    // CDI

    canvas.save();
    rotate((pfd.to - pfd.yaw + 360) % 360, _x(0), _y(-95));
    //draw dots for displacement.
    paintFill.color = Colors.white;

    for(double i = 0; i < 25; i += 5) {
      drawCircle(_x(-5 - i), _y(-95), _y(0) - _y(1), paintFill);
      drawCircle(_x( 5 + i), _y(-95), _y(0) - _y(1), paintFill);
    }

    paintStroke.color = Colors.purpleAccent;
    paintFill.color = Colors.purpleAccent;
    paintStroke.strokeWidth = 2;
    drawLine(_x(0), _y(-115), _x(0), _y(-105), paintStroke); // three to break up CDI
    drawLine(_x(0), _y(-85), _x(0), _y(-80), paintStroke);
    path.reset();
    path.moveTo(_x(0), _y(-75));
    path.lineTo(_x(-5), _y(-80));
    path.lineTo(_x(5), _y(-80));
    canvas.drawPath(path, paintFill);
    drawLine(_x(pfd.cdi * 5), _y(-105), _x(pfd.cdi * 5), _y(-85), paintStroke);
    canvas.restore();


    //draw course
    paintFill.color = Colors.black;
    drawRect(_x(45), _y(-70), _x(71), _y(-78), paintFill);
    paintStroke.color = Colors.white;
    drawRect(_x(45), _y(-70), _x(71), _y(-78), paintStroke);
    drawText("${((pfd.to + 360) % 360).round()}\u00B0", _x(48), _y(-74));

    /*
     * draw VDI
     */

    // boundary
    drawRect(_x(45), _y(25), _x(50), _y(-25), paintStroke);
    drawLine(_x(45), _y(0), _x(50), _y(0), paintStroke);

    //draw bars in 10s

    paintFill.color = Colors.white;

    drawCircle(_x(47.5), _y(vnavBarDegree * 4 * vdiDegree), _y(0) - _y(1), paintFill);
    drawCircle(_x(47.5), _y(vnavBarDegree * 2 * vdiDegree), _y(0) - _y(1), paintFill);
    drawCircle(_x(47.5), _y(-vnavBarDegree * 2 * vdiDegree), _y(0) - _y(1), paintFill);
    drawCircle(_x(47.5), _y(-vnavBarDegree * 4 * vdiDegree), _y(0) - _y(1), paintFill);

    //draw VDI circle
    if(pfd.vdi >= vnavHigh) {
      paintFill.color = Colors.purpleAccent;
    }
    else if(pfd.vdi <= vnavLow) {
      paintFill.color = Colors.purpleAccent;
    }
    else {
      paintFill.color = Colors.cyan;
    }

    double val = 3 - pfd.vdi;
    drawCircle(_x(47.5), _y(val * vdiDegree), _y(0) - _y(1), paintFill);

    drawText("G", _x(44), _y(28));

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class PfdData {
  double roll = 0;
  double pitch = 0;
  double yaw = 0;
  double aoa = 0;
  double slip = 0;
  double speed = 0;
  double speedChange = 0;
  double altitude = 0;
  double altitudeChange = 0;
  double vsi = 0;
  double cdi = 0;
  double turnTrend = 0;
  double to = 0;
  double vdi = 0;
}