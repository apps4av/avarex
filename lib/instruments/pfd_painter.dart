import 'dart:math';

import 'package:avaremp/instruments/cdi_vdi.dart';
import 'package:avaremp/instruments/pfd_runway.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/elevation_tile_provider.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

class PfdPainter extends CustomPainter {


  PfdPainter({required Listenable repaint, required height, required width}) : super(repaint: repaint) {
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

  static const double _obsKnobY = -68;

  /// Xform 0,0 in center, and (100, 100) on top right, and (-100, -100) on bottom left
  static double yOf(double yval, double height) {
    return height / 2 - yval * (height / 200) - height * yPan;
  }

  static double xOf(double xval, double width) {
    return width / 2 + xval * (width / 200);
  }

  double _y(double yval) => yOf(yval, _height);

  double _x(double xval) => xOf(xval, _width);

  static Offset compassCenter(double width, double height) =>
      Offset(xOf(0, width), yOf(-95, height));

  static double compassRadius(double height) =>
      (yOf(-65, height) - yOf(-95, height)).abs();

  static double obsKnobRadius(double height) => yOf(0, height) - yOf(3, height);

  static double obsHitRadius(double height) => max(28, obsKnobRadius(height) * 2.5);

  /// True if [local] is on the CDI rose, where OBS can be set.
  static bool onCompassRing(Offset local, double width, double height) {
    final double d = (local - compassCenter(width, height)).distance;
    final double r = compassRadius(height);
    return d >= r * 0.25 && d <= r * 2.4;
  }

  /// OBS knob on the CDI rose, at the selected course.
  static Offset obsKnobOffset(
      double width, double height, double yaw, double course) {
    final Offset c = compassCenter(width, height);
    final double dx = xOf(0, width) - c.dx;
    final double dy = yOf(_obsKnobY, height) - c.dy;
    final double a = (course - yaw) * pi / 180;
    return Offset(c.dx + dx * cos(a) - dy * sin(a),
        c.dy + dx * sin(a) + dy * cos(a));
  }

  /// Magnetic heading under a pointer on the compass. 12 o'clock is current yaw.
  static double headingAt(
      Offset local, double width, double height, double yaw) {
    final Offset c = compassCenter(width, height);
    final double deg = atan2(local.dx - c.dx, c.dy - local.dy) * 180 / pi;
    return (yaw + deg + 360) % 360;
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

    // synthetic terrain then runway, same horizon frame as pitch / roll
    _drawTerrain(canvas, pfd);
    _drawRunway(canvas, pfd);

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
    final double cdi = pfd.displayedCdi;
    drawLine(_x(cdi * 5), _y(-105), _x(cdi * 5), _y(-85), paintStroke);
    // OBS selector knob on the selected course.
    paintFill.color = pfd.obs == null ? Colors.amber : Colors.cyan;
    paintStroke.color = Colors.white;
    paintStroke.strokeWidth = 1.5;
    drawCircle(_x(0), _y(_obsKnobY), _y(0) - _y(3), paintFill);
    drawCircle(_x(0), _y(_obsKnobY), _y(0) - _y(3), paintStroke);
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
    drawCircle(_x(47.5), _y(val * vdiDegree), _y(0) - _y(1.5), paintFill);

    drawText("G", _x(44), _y(28));

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }

  // ------------------------------------------------------------------
  // Synthetic runway (pilot's perspective)
  // ------------------------------------------------------------------

  /// Points closer than this (ft) along the view axis are clipped.
  static const double _zNear = 3;

  /// Half field of view kept after clipping, as tan(angle). 3 ≈ 71.5°, which
  /// bounds projected coordinates to about 3.4 × height from the center.
  static const double _frustumK = 3;

  /// Pilot eye height above the pavement when GPS says we are on / below it.
  static const double _eyeHeightFt = 6;

  static const Color _surfaceColor = Color(0xE6404040);
  static final Color _markingColor = Colors.white.withValues(alpha: 0.9);
  static const Color _terrainBrown = Color(0xFF624624);
  static const Color _terrainRed = Color(0xCCFF0000);

  /// Focal length in pixels, chosen so one degree of elevation at the center
  /// of view spans the same pixels as one degree on the pitch ladder.
  double get _focalPx => (_height / 200) * pitchDegree / tan(pi / 180);

  void _drawTerrain(Canvas canvas, PfdData pfd) {
    final PfdTerrain? mesh = pfd.terrain;
    if (mesh == null || mesh.cols < 2 || mesh.rows < 2) return;
    final double lat;
    final double lon;
    final double altFt;
    final double trackTrue;
    try {
      final pos = Storage().position;
      lat = pos.latitude;
      lon = pos.longitude;
      altFt = GeoCalculations.convertAltitude(pos.altitude);
      trackTrue = pos.heading;
    } catch (_) {
      return;
    }
    final double headingTrue = pfd.ahrsHeadingLive
        ? (pfd.yaw + Storage().area.variation + 360) % 360
        : trackTrue;
    final double h = GeoCalculations.toRadians(headingTrue);
    final double cosH = cos(h);
    final double sinH = sin(h);
    final double cosLat = cos(GeoCalculations.toRadians(lat));
    final double? ground = Storage().area.elevation;
    // Sit above the surface so a level look still sees a receding 3D floor,
    // and so hills rise into the sky instead of painting the horizon.
    final double camUp = max(altFt, ground ?? altFt) + 20;
    final double f = _focalPx;
    final double cx = _x(0);
    final double cy = _y(0);

    _P3 camAt(LatLng p, double elev) {
      final double n = (p.latitude - lat) * PfdRunwayEnd.ftPerDegLat;
      final double e = (p.longitude - lon) * PfdRunwayEnd.ftPerDegLat * cosLat;
      final double dU = elev - camUp - (n * n + e * e) / (2 * PfdRunwayEnd.earthRadiusFt);
      return _P3(e * cosH - n * sinH, dU, n * cosH + e * sinH);
    }

    Offset project(_P3 p) => Offset(cx + f * p.x / p.z, cy - f * p.y / p.z);

    Color bandColor(double elev) =>
        PfdTerrain.isRed(elev, altFt) ? _terrainRed : _terrainBrown;

    final Paint fill = Paint()..style = PaintingStyle.fill;
    void facet(_P3 a, _P3 b, _P3 c, _P3 d, Color base) {
      final List<_P3> clip = (a.z > 40 && b.z > 40 && c.z > 40 && d.z > 40)
          ? [a, b, c, d]
          : _clipPolygon([a, b, c, d]);
      if (clip.length < 3) return;
      fill.color = base;
      final Path path = Path()..moveTo(project(clip[0]).dx, project(clip[0]).dy);
      for (int i = 1; i < clip.length; i++) {
        final Offset o = project(clip[i]);
        path.lineTo(o.dx, o.dy);
      }
      path.close();
      canvas.drawPath(path, fill);
    }

    // Far rows first so nearer slopes occlude distant ones.
    for (int r = mesh.rows - 2; r >= 0; r--) {
      for (int c = 0; c < mesh.cols - 1; c++) {
        final int i00 = r * mesh.cols + c;
        final int i10 = i00 + 1;
        final int i01 = i00 + mesh.cols;
        final int i11 = i01 + 1;
        final double? e00 = mesh.elevFt[i00];
        final double? e10 = mesh.elevFt[i10];
        final double? e01 = mesh.elevFt[i01];
        final double? e11 = mesh.elevFt[i11];
        if (e00 == null || e10 == null || e01 == null || e11 == null) continue;
        facet(
          camAt(mesh.pts[i00], e00),
          camAt(mesh.pts[i10], e10),
          camAt(mesh.pts[i11], e11),
          camAt(mesh.pts[i01], e01),
          bandColor(max(max(e00, e10), max(e01, e11))),
        );
      }
    }
  }

  void _drawRunway(Canvas canvas, PfdData pfd) {
    final PfdRunwayEnd? rw = pfd.runway;
    if (rw == null) {
      return;
    }
    final double lat;
    final double lon;
    final double altFt;
    final double trackTrue;
    try {
      final pos = Storage().position;
      lat = pos.latitude;
      lon = pos.longitude;
      altFt = GeoCalculations.convertAltitude(pos.altitude);
      trackTrue = pos.heading;
    } catch (_) {
      return; // no position yet
    }

    // Camera in the runway frame.
    final (camAlong, camCross) = rw.frameOf(lat, lon);
    final double camUp = max(altFt, rw.elevationAt(camAlong) + _eyeHeightFt);
    final double headingTrue = pfd.ahrsHeadingLive
        ? (pfd.yaw + Storage().area.variation + 360) % 360
        : trackTrue;
    final double rel = GeoCalculations.toRadians(headingTrue - rw.headingTrue);
    final double cosR = cos(rel);
    final double sinR = sin(rel);
    final double f = _focalPx;
    final double cx = _x(0);
    final double cy = _y(0);

    // Runway frame (along, cross, up) -> camera frame (x right, y up, z fwd).
    _P3 cam(double along, double cross, [double? up]) {
      final double dA = along - camAlong;
      final double dC = cross - camCross;
      final double dU = (up ?? rw.elevationAt(along)) - camUp
          - (dA * dA + dC * dC) / (2 * PfdRunwayEnd.earthRadiusFt);
      return _P3(dC * cosR - dA * sinR, dU, dA * cosR + dC * sinR);
    }

    Offset project(_P3 p) => Offset(cx + f * p.x / p.z, cy - f * p.y / p.z);

    final Paint fill = Paint()..style = PaintingStyle.fill;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _markingColor;

    void polygon(List<_P3> pts, Color color) {
      final List<_P3> c = _clipPolygon(pts);
      if (c.length < 3) return;
      final Path path = Path()..moveTo(project(c[0]).dx, project(c[0]).dy);
      for (int i = 1; i < c.length; i++) {
        final Offset o = project(c[i]);
        path.lineTo(o.dx, o.dy);
      }
      path.close();
      fill.color = color;
      canvas.drawPath(path, fill);
    }

    void line(_P3 a, _P3 b) {
      final List<_P3>? c = _clipSegment(a, b);
      if (c == null) return;
      canvas.drawLine(project(c[0]), project(c[1]), stroke);
    }

    // Quad in runway frame: along a0..a1, cross c0..c1.
    void quad(double a0, double a1, double c0, double c1, Color color) {
      polygon([cam(a0, c0), cam(a0, c1), cam(a1, c1), cam(a1, c0)], color);
    }

    final double w = rw.widthFt;
    final double hw = w / 2;
    final double len = rw.lengthFt;
    final double thr = rw.displacedFt;
    final double farThr = len - rw.farDisplacedFt;
    final double usable = farThr - thr;

    // Pavement and edges.
    quad(0, len, -hw, hw, _surfaceColor);
    line(cam(0, -hw), cam(len, -hw));
    line(cam(0, hw), cam(len, hw));
    line(cam(0, -hw), cam(0, hw));
    line(cam(len, -hw), cam(len, hw));

    // Centerline paint width. FAA is 3 ft; that vanishes on a phone-sized PFD,
    // so we draw a stripe wide enough to read from a couple of miles out.
    final double clw = max(8.0, w * 0.10);

    // Displaced threshold, AIM FIG 2-3-4: arrows along the former centerline
    // (shaft + head) and a row of arrowheads just before the 10 ft bar.
    // No dashed centerline in this area.
    if (thr > 0) {
      const double shaftLen = 90;
      const double headLen = 28;
      final double headHalf = min(16.0, hw * 0.28);
      void arrow(double tip) {
        final double base = tip - headLen;
        final double tail = base - shaftLen;
        if (tail < 0) return;
        quad(tail, base, -clw / 2, clw / 2, _markingColor);
        polygon([
          cam(tip, 0),
          cam(base, -headHalf),
          cam(base, headHalf),
        ], _markingColor);
      }
      // Space arrows so the last shaft stays clear of the arrowhead row.
      for (double tip = 40 + shaftLen + headLen; tip < thr - 70; tip += 200) {
        arrow(tip);
      }
      // Four (or six) arrowheads across the width, immediately before the bar.
      final int heads = w >= 150 ? 6 : 4;
      final double span = hw * 0.72;
      final double rowTip = thr - 14;
      final double rowBase = rowTip - 22;
      for (int k = 0; k < heads; k++) {
        final double c = -span + (2 * span) * (k + 0.5) / heads;
        polygon([
          cam(rowTip, c),
          cam(rowBase, c - headHalf * 0.7),
          cam(rowBase, c + headHalf * 0.7),
        ], _markingColor);
      }
      quad(thr - 10, thr, -hw, hw, _markingColor); // 10 ft threshold bar
    }
    line(cam(thr, -hw), cam(thr, hw));
    line(cam(farThr, -hw), cam(farThr, hw));

    // Threshold stripes, count per FAA runway width table.
    int stripes = w <= 60 ? 4 : w <= 75 ? 6 : w <= 100 ? 8 : w <= 150 ? 12 : 16;
    while (stripes > 2 && (stripes / 2) * 11.5 > hw - 3) {
      stripes -= 2;
    }
    void thresholdStripes(double a0, double a1) {
      for (int k = 0; k < stripes ~/ 2; k++) {
        final double c0 = 5.75 + k * 11.5;
        final double c1 = c0 + 5.75;
        quad(a0, a1, c0, c1, _markingColor);
        quad(a0, a1, -c1, -c0, _markingColor);
      }
    }
    if (usable > 400) {
      thresholdStripes(thr + 20, thr + 170);
      thresholdStripes(farThr - 170, farThr - 20);
    }

    // Runway designation, AIM: after the threshold stripes, on the centerline.
    // Leave a gap so the dashed centerline does not run through the numbers.
    const double numGapAfterStripes = 20;
    const double numGapBeforeCl = 40;
    double numH = 60;
    double nearNum0 = 0, nearNum1 = 0, farNum0 = 0, farNum1 = 0;
    bool drawNums = usable > 500;
    if (drawNums) {
      numH = min(60.0, (usable - 400) / 2).clamp(28.0, 60.0);
      nearNum0 = thr + 170 + numGapAfterStripes;
      nearNum1 = nearNum0 + numH;
      farNum1 = farThr - 170 - numGapAfterStripes;
      farNum0 = farNum1 - numH;
      if (farNum0 < nearNum1 + 80) {
        drawNums = false;
      }
    }

    // Thousand-foot (aiming point) markers.
    if (usable >= 2400) {
      quad(thr + 1000, thr + 1150, 0.24 * w, 0.44 * w, _markingColor);
      quad(thr + 1000, thr + 1150, -0.44 * w, -0.24 * w, _markingColor);
    }

    // Centerline: 120 ft stripes, 80 ft gaps. Starts after the near number
    // and stops before the far number.
    final double cl0 = drawNums ? nearNum1 + numGapBeforeCl : thr + 200;
    final double cl1 = drawNums ? farNum0 - numGapBeforeCl : farThr - 200;
    for (double a = cl0; a + 120 <= cl1; a += 200) {
      quad(a, a + 120, -clw / 2, clw / 2, _markingColor);
    }

    if (drawNums) {
      _paintRunwayIdent(canvas, rw.ident, nearNum0, nearNum1, w, cam, project);
      _paintRunwayIdent(canvas, rw.farIdent, farNum1, farNum0, w, cam, project);
    }
  }

  /// Paint [ident] on the pavement. [alongBottom] is the threshold side of
  /// the digits (bottom), [alongTop] the far side (top), so the number reads
  /// correctly on that approach.
  void _paintRunwayIdent(
    Canvas canvas,
    String ident,
    double alongBottom,
    double alongTop,
    double runwayW,
    _P3 Function(double, double, [double?]) cam,
    Offset Function(_P3) project,
  ) {
    if (ident.isEmpty) return;
    paintText.text = TextSpan(
      text: ident,
      style: TextStyle(
        color: _markingColor,
        fontWeight: FontWeight.w900,
        fontSize: 120,
        height: 1.0,
        letterSpacing: 6,
      ),
    );
    paintText.layout();
    final double tw = paintText.width;
    final double th = paintText.height;
    if (tw < 1 || th < 1) return;

    final double hFt = (alongTop - alongBottom).abs();
    double wFt = hFt * tw / th;
    if (wFt > runwayW * 0.62) {
      wFt = runwayW * 0.62;
    }
    final double half = wFt / 2;
    final _P3 tl = cam(alongTop, -half);
    final _P3 tr = cam(alongTop, half);
    final _P3 bl = cam(alongBottom, -half);
    if (tl.z < _zNear || tr.z < _zNear || bl.z < _zNear) return;

    final Offset ptl = project(tl);
    final Offset ptr = project(tr);
    final Offset pbl = project(bl);
    canvas.save();
    canvas.transform((Matrix4.identity()
          ..setEntry(0, 0, (ptr.dx - ptl.dx) / tw)
          ..setEntry(1, 0, (ptr.dy - ptl.dy) / tw)
          ..setEntry(0, 1, (pbl.dx - ptl.dx) / th)
          ..setEntry(1, 1, (pbl.dy - ptl.dy) / th)
          ..setEntry(0, 3, ptl.dx)
          ..setEntry(1, 3, ptl.dy))
        .storage);
    paintText.paint(canvas, Offset.zero);
    canvas.restore();
  }

  /// Signed distance of [p] from each frustum plane; >= 0 is inside.
  static double _planeDist(int plane, _P3 p) {
    switch (plane) {
      case 0: return p.z - _zNear;
      case 1: return p.z * _frustumK + p.x;
      case 2: return p.z * _frustumK - p.x;
      case 3: return p.z * _frustumK + p.y;
      default: return p.z * _frustumK - p.y;
    }
  }

  /// Sutherland–Hodgman polygon clip against the view frustum.
  static List<_P3> _clipPolygon(List<_P3> input) {
    List<_P3> out = input;
    for (int plane = 0; plane < 5 && out.isNotEmpty; plane++) {
      final List<_P3> inPts = out;
      out = [];
      for (int i = 0; i < inPts.length; i++) {
        final _P3 a = inPts[i];
        final _P3 b = inPts[(i + 1) % inPts.length];
        final double da = _planeDist(plane, a);
        final double db = _planeDist(plane, b);
        if (da >= 0) out.add(a);
        if ((da >= 0) != (db >= 0)) {
          out.add(_P3.lerp(a, b, da / (da - db)));
        }
      }
    }
    return out;
  }

  /// Clip a segment against the view frustum; null if fully outside.
  static List<_P3>? _clipSegment(_P3 a, _P3 b) {
    double t0 = 0, t1 = 1;
    for (int plane = 0; plane < 5; plane++) {
      final double da = _planeDist(plane, a);
      final double db = _planeDist(plane, b);
      if (da < 0 && db < 0) return null;
      if (da >= 0 && db >= 0) continue;
      final double t = da / (da - db);
      if (da < 0) {
        t0 = max(t0, t);
      } else {
        t1 = min(t1, t);
      }
      if (t0 > t1) return null;
    }
    return [_P3.lerp(a, b, t0), _P3.lerp(a, b, t1)];
  }
}

class _P3 {
  final double x;
  final double y;
  final double z;
  const _P3(this.x, this.y, this.z);

  static _P3 lerp(_P3 a, _P3 b, double t) =>
      _P3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
}

class PfdData {
  /// AHRS data older than this is treated as absent.
  static const int ahrsStaleMs = 5000;

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
  /// Preferred CDI (dots, ±5). Null until a source publishes one.
  double? cdi;
  /// GPS-derived CDI used when [cdi] has been unset for [ahrsStaleMs].
  double gpsCdi = 0;
  double turnTrend = 0;
  double to = 0;
  /// Manual OBS course in degrees magnetic. Null follows GPS/route course.
  double? obs;
  double vdi = 0;

  /// Wall clock (ms) of the last ADS-B AHRS pitch/roll and heading samples.
  int lastAttitudeMs = 0;
  int lastHeadingMs = 0;
  /// Wall clock (ms) of the last preferred CDI publish.
  int lastCdiMs = 0;

  /// Runway end chosen for the synthetic-vision background, or null.
  PfdRunwayEnd? runway;

  /// Elevation-tile heightmap for the synthetic-vision ground, or null.
  PfdTerrain? terrain;

  bool get ahrsAttitudeLive =>
      DateTime.now().millisecondsSinceEpoch - lastAttitudeMs < ahrsStaleMs;
  bool get ahrsHeadingLive =>
      DateTime.now().millisecondsSinceEpoch - lastHeadingMs < ahrsStaleMs;
  bool get cdiLive =>
      cdi != null &&
      DateTime.now().millisecondsSinceEpoch - lastCdiMs < ahrsStaleMs;

  /// Needle value: preferred [cdi] while live, otherwise the GPS calculation.
  double get displayedCdi {
    final double value = cdiLive ? cdi! : gpsCdi;
    if (value > 5) {
      return 5;
    }
    if (value < -5) {
      return -5;
    }
    return value;
  }

  void setCdi(double value) {
    cdi = value;
    lastCdiMs = DateTime.now().millisecondsSinceEpoch;
  }
}

/// Heightmap sampled from elevation tiles. [elevFt] is row-major
/// (index = row * cols + col). Null elevation means no tile at that point.
class PfdTerrain {
  final List<LatLng> pts;
  final List<double?> elevFt;
  final int cols;
  final int rows;

  const PfdTerrain({
    required this.pts,
    required this.elevFt,
    required this.cols,
    required this.rows,
  });

  /// Same red test as the map Elevation layer (elev ≥ altitude − 500 ft).
  static bool isRed(double elevFt, double altFt) =>
      ElevationImageProvider.isRed(elevFt, altFt);
}

/// PFD panel with a draggable OBS knob on the CDI compass.
class PfdView extends StatefulWidget {
  final double width;
  final double height;

  const PfdView({super.key, required this.width, required this.height});

  @override
  State<PfdView> createState() => _PfdViewState();
}

class _PfdViewState extends State<PfdView> {
  static const Duration _doubleTap = Duration(milliseconds: 350);
  static const double _doubleTapSlop = 36;
  static const double _dragSlop = 8;

  bool _draggingObs = false;
  bool _obsArmed = false;
  Offset? _downPos;
  DateTime? _lastTapAt;
  Offset? _lastTapPos;
  late final Listenable _repaint;

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge([Storage().timeChange, Storage().pfdChange]);
  }

  bool _hitObs(Offset local) {
    final PfdData pfd = Storage().pfdData;
    final Offset knob = PfdPainter.obsKnobOffset(
        widget.width, widget.height, pfd.yaw, pfd.to);
    if ((local - knob).distance <= PfdPainter.obsHitRadius(widget.height)) {
      return true;
    }
    return PfdPainter.onCompassRing(local, widget.width, widget.height);
  }

  void _dragObs(Offset local) {
    Cdi.setObs(PfdPainter.headingAt(
        local, widget.width, widget.height, Storage().pfdData.yaw));
  }

  void _endPointer() {
    _draggingObs = false;
    _obsArmed = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent e) {
        final Offset local = e.localPosition;
        if (!_hitObs(local)) {
          return;
        }
        final DateTime now = DateTime.now();
        if (_lastTapAt != null &&
            now.difference(_lastTapAt!) <= _doubleTap &&
            _lastTapPos != null &&
            (local - _lastTapPos!).distance <= _doubleTapSlop) {
          _lastTapAt = null;
          _lastTapPos = null;
          _endPointer();
          Cdi.setObs(null);
          return;
        }
        _lastTapAt = now;
        _lastTapPos = local;
        _downPos = local;
        _obsArmed = true;
        _draggingObs = false;
      },
      onPointerMove: (PointerMoveEvent e) {
        final Offset local = e.localPosition;
        if (_draggingObs) {
          _dragObs(local);
          return;
        }
        if (_obsArmed &&
            _downPos != null &&
            (local - _downPos!).distance >= _dragSlop) {
          _draggingObs = true;
          _obsArmed = false;
          _lastTapAt = null;
          _dragObs(local);
        }
      },
      onPointerUp: (_) => _endPointer(),
      onPointerCancel: (_) => _endPointer(),
      child: CustomPaint(
        size: Size(widget.width, widget.height),
        painter: PfdPainter(
          height: widget.height,
          width: widget.width,
          repaint: _repaint,
        ),
      ),
    );
  }
}