import 'dart:math';

import 'package:flutter/material.dart';

class PfdPainter extends CustomPainter {

  PfdPainter(this.mHeight, this.mWidth);

  final double mHeight;
  final double mWidth;
  final double mRoll = 0;
  final double mPitch = 0;
  final double mYaw = 0;
  final double mAoa = 0;
  final double mInclinometer = 0;
  final double mSpeed = 0;
  final double mSpeedChange = 0;
  final double mAltitude = 0;
  final double mAltitudeChange = 0;
  final double mVsi = 0;
  final double mCdi = 0;
  final double mTurnTrend = 0;
  final double mTo = 0;
  final double mVdi = 0;

  TextPainter mPaintText = TextPainter();

  static const double SPEED_TEN = 1.5;
  static const double ALTITUDE_THOUSAND = 1.5;
  static const double VSI_FIVE = 1.5;
  static const double PITCH_DEGREE = 4;
  static const double VDI_DEGREE = 30;

  static const double VNAV_BAR_DEGREES = 0.14;
  static const double VNAV_APPROACH_DISTANCE = 15;

  static const double VNAV_HI = 3.7;
  static const double VNAV_LOW = 2.3;

  /// PAn the whole drawing up with this fraction of screen to utilize maximum screen
  static const double Y_PAN = 0.125;

  /// Xform 0,0 in center, and (100, 100) on top right, and (-100, -100) on bottom left
  /// @param yval
  /// @return
  double y(double yval) {
    double yperc = mHeight / 200;
    return mHeight / 2 - yval * yperc - mHeight * Y_PAN;
  }

  /// Xform 0,0 in center, and (100, 100) on top right, and (-100, -100) on bottom left
  /// @param xval
  /// @return
  double x(double xval) {
    double xperc = mWidth / 200;
    return mWidth / 2 + xval * xperc;
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
      TextSpan span = TextSpan(text: value, style: TextStyle(fontSize: mHeight / 40));
      mPaintText.textAlign = TextAlign.left;
      mPaintText.textDirection = TextDirection.ltr;
      mPaintText.text = span;
      mPaintText.layout();
      mPaintText.paint(canvas, Offset(x, y - mPaintText.height / 2));
    }


    Paint paintFill = Paint();
    paintFill.style = PaintingStyle.fill;

    Paint paintStroke = Paint();
    paintStroke.style = PaintingStyle.stroke;
    paintStroke.color = Colors.white;
    paintStroke.strokeWidth = 1.5;

    /*
     * draw pitch / roll
     */
    canvas.save();


    rotate(mRoll, x(0), y(0));
    canvas.translate(0, y(0) - y(mPitch * PITCH_DEGREE));

    paintFill.color = Colors.blueAccent;
    drawRect(x(-400), y(PITCH_DEGREE * 90), x(400), y(0), paintFill);

    paintFill.color = const Color(0xFF826644);
    drawRect(x(-400), y(0), x(400), y(-PITCH_DEGREE * 90), paintFill);

    //center attitude degrees
    drawLine(x(-150), y(0), x(150), y(0), paintStroke);

    // degree lines
    double degrees = (((mPitch + 1.25) / 2.5).round().toDouble() * 2.5);

    for(double d = -12.5; d <= 12.5; d += 2.5) {
      double inc = degrees + d;
      if (0 == inc % 10) {
        drawLine(x(-12), y(inc * PITCH_DEGREE), x(12), y(inc * PITCH_DEGREE), paintStroke);
        if(0 == inc) {
          continue;
        }
        drawText("${inc.abs().round()}", x(12), y(inc * PITCH_DEGREE));
      }
      if (0 == inc % 5) {
        drawLine(x(-4), y(inc * PITCH_DEGREE), x(4), y(inc * PITCH_DEGREE), paintStroke);
      }
      else {
        drawLine(x(-2), y(inc * PITCH_DEGREE), x(2), y(inc * PITCH_DEGREE), paintStroke);
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

    if(mAoa > (1 - 1/6)) {
      c9 = Colors.red;
    }
    if(mAoa > (1 - 2/6)) {
      c8 = Colors.red;
    }
    if (mAoa > (1 - 2.5/6)) {
      c7 = Colors.yellow;
    }
    if (mAoa > (1 - 3/6)) {
      c6 = Colors.yellow;
    }
    if (mAoa > (1 - 3.5/6)) {
      c5 = Colors.yellow;
    }
    if (mAoa > (1 - 4/6)) {
      c4 = Colors.yellow;
    }
    if (mAoa > (1 - 4.5/6)) {
      c3 = Colors.green;
    }
    if (mAoa > (1 - 5.0/6)) {
      c2 = Colors.green;
    }
    if (mAoa >= (0)) {
      c1 = Colors.green;
    }

    paintFill.color = Colors.black;
    Path path = Path();
    path.reset();
    path.moveTo(x(-45) , y(31));
    path.lineTo(x(-45), y(5));
    path.lineTo(x(-25), y(5));
    path.lineTo(x(-25), y(31));

    canvas.drawPath(path, paintFill);

    paintStroke.color = c1;
    drawLine(x(-44), y(6), x(-26), y(6), paintStroke);

    paintStroke.color = c2;
    drawLine(x(-44), y(9), x(-26), y(9), paintStroke);

    paintStroke.color = c3;
    drawLine(x(-44), y(12), x(-38), y(12), paintStroke);
    drawLine(x(-32), y(12), x(-26), y(12), paintStroke);
    drawCircle(x(-35), y(12), 4, paintStroke);

    paintStroke.color = c4;
    drawLine(x(-44), y(15), x(-26), y(15), paintStroke);

    paintStroke.color = c5;
    drawLine(x(-44), y(18), x(-38), y(18), paintStroke);
    drawLine(x(-32), y(18), x(-26), y(18), paintStroke);

    //chevrons
    paintStroke.color = c6;
    drawLine(x(-44), y(21), x(-35), y(18), paintStroke);
    drawLine(x(-35), y(18), x(-26), y(21), paintStroke);

    paintStroke.color = c7;
    drawLine(x(-44), y(24), x(-35), y(21), paintStroke);
    drawLine(x(-35), y(21), x(-26), y(24), paintStroke);

    paintStroke.color = c8;
    drawLine(x(-44), y(27), x(-35), y(24), paintStroke);
    drawLine(x(-35), y(24), x(-26), y(27), paintStroke);

    paintStroke.color = c9;
    drawLine(x(-44), y(30), x(-35), y(27), paintStroke);
    drawLine(x(-35), y(27), x(-26), y(30), paintStroke);

    canvas.restore();


    canvas.save();

    rotate(mRoll, x(0), y(0));

    //draw roll arc
    paintFill.color = Colors.white;
    paintStroke.color = Colors.white;
    double r = y(0) - y(70);
    Rect rect = Rect.fromLTRB(x(0) - r, y(0) - r, x(0) + r, y(0) + r);
    canvas.drawArc(rect, 210 * pi / 180, 120 * pi / 180, false, paintStroke);

    // degree ticks
    //60
    rotate(-60, x(0), y(0));
    drawLine(x(0), y(75), x(0), y(70), paintStroke);

    //45
    rotate(15, x(0), y(0));
    drawLine(x(0), y(73), x(0), y(70), paintStroke);

    //30
    rotate(15, x(0), y(0));
    drawLine(x(0), y(75), x(0), y(70), paintStroke);

    //20
    rotate(10, x(0), y(0));
    drawLine(x(0), y(73), x(0), y(70), paintStroke);

    //10
    rotate(10, x(0), y(0));
    drawLine(x(0), y(73), x(0), y(70), paintStroke);


    // center arrow
    rotate(10, x(0), y(0));
    path.reset();
    path.moveTo(x(-7), y(75));
    path.lineTo(x(0), y(70));
    path.lineTo(x(7), y(75));
    canvas.drawPath(path, paintFill);

    //10
    rotate(10, x(0), y(0));
    drawLine(x(0), y(73), x(0), y(70), paintStroke);

    //20
    rotate(10, x(0), y(0));
    drawLine(x(0), y(73), x(0), y(70), paintStroke);

    //30
    rotate(10, x(0), y(0));
    drawLine(x(0), y(75), x(0), y(70), paintStroke);

    //45
    rotate(15, x(0), y(0));
    drawLine(x(0), y(73), x(0), y(70), paintStroke);

    //60
    rotate(15, x(0), y(0));
    drawLine(x(0), y(73), x(0), y(70), paintStroke);

    rotate(-60, x(0), y(0));


    canvas.restore();

    //bank arrow
    path.reset();
    path.moveTo(x(7), y(65));
    path.lineTo(x(0), y(70));
    path.lineTo(x(-7), y(65));
    canvas.drawPath(path, paintFill);

    // inclinometer, displace +-20 of screen from +- 10 degrees
    drawRect(x(-7 + mInclinometer * 2), y(64), x(7 + mInclinometer * 2), y(62), paintFill);


    // draw airplane wings
    paintFill.color = Colors.yellow;
    drawRect(x(-45), y(1), x(-20), y(-1), paintFill);
    drawRect(x(20), y(1), x(45), y(-1), paintFill);

    // draw airplane triangle
    path.reset();
    path.moveTo(x(0) , y(0));
    path.lineTo(x(-15), y(-10));
    path.lineTo(x(0), y(-5));
    path.lineTo(x(15), y(-10));
    canvas.drawPath(path, paintFill);

    /**
     * Speed tape
     */
    paintStroke.color = Colors.white;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(x(-80), y(35), x(-50), y(-35)));
    canvas.translate(0, y(0) - y(mSpeed * SPEED_TEN));

    // lines, just draw + - 30
    double tens = (mSpeed / 10).round() * 10;
    for(double c = tens - 30; c <= tens + 30; c += 10) {
      if(c < 0) {
        continue; // no negative speed
      }
      drawLine(x(-50), y(c * SPEED_TEN), x(-55), y(c * SPEED_TEN), paintStroke);
      drawText("${c.abs().round()}", x(-75), y(c * SPEED_TEN));

    }
    for(double c = tens - 30; c <= tens + 30; c += 5) {
      if(c < 0) {
        continue; // no negative speed
      }
      drawLine(x(-50), y(c * SPEED_TEN), x(-53), y(c * SPEED_TEN), paintStroke);
    }

    canvas.restore();

    // trend
    paintFill.color = Colors.purpleAccent;
    if(mSpeedChange > 0) {
      drawRect(x(-53), y(mSpeedChange * SPEED_TEN), x(-50), y(0), paintFill);
    }
    else {
      drawRect(x(-53), y(0), x(-50), y(mSpeedChange * SPEED_TEN), paintFill);
    }

    // value
    paintFill.color = Colors.black;

    path.reset();
    path.moveTo(x(-80), y(3));
    path.lineTo(x(-55), y(3));
    path.lineTo(x(-50), y(0));
    path.lineTo(x(-55), y(-3));
    path.lineTo(x(-80), y(-3));
    canvas.drawPath(path, paintFill);

    drawText("${mSpeed.abs().round()}", x(-75), y(0));
    // boundary
    paintStroke.color = Colors.white;
    drawRect(x(-80), y(35), x(-50), y(-35), paintStroke);


    /**
     * Altitude tape
     */
    paintStroke.color = Colors.white;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(x(35), y(35), x(85), y(-35)));
    canvas.translate(0, y(0) - y(mAltitude * ALTITUDE_THOUSAND / 10)); // alt is dealt in 10's of feet

    // lines, just draw + and - 300 ft.
    double hundreds = (mAltitude / 100).round() * 100;
    for(double c = (hundreds - 300) / 10; c <= (hundreds + 300) / 10; c += 10) {
      drawLine(x(50), y(c * ALTITUDE_THOUSAND), x(55), y(c * ALTITUDE_THOUSAND), paintStroke);

      drawText("${c.round()}0", x(55), y(c * ALTITUDE_THOUSAND));
    }
    for(double c = (hundreds - 300) / 10; c <= (hundreds + 300) / 10; c += 2) {
      drawLine(x(50), y(c * ALTITUDE_THOUSAND), x(53), y(c * ALTITUDE_THOUSAND), paintStroke);
    }
    canvas.restore();

    // trend
    paintFill.color = Colors.purpleAccent;
    if(mAltitudeChange > 0) {
      drawRect(x(50), y(mAltitudeChange * ALTITUDE_THOUSAND / 10), x(52), y(0), paintFill);
    }
    else {
      drawRect(x(50), y(0), x(52), y(mAltitudeChange * ALTITUDE_THOUSAND / 10), paintFill);
    }

    // value
    paintFill.color = Colors.black;

    path.reset();
    path.moveTo(x(50), y(0));
    path.lineTo(x(55), y(3));
    path.lineTo(x(85), y(3));
    path.lineTo(x(85), y(-3));
    path.lineTo(x(55), y(-3));
    canvas.drawPath(path, paintFill);

    drawText("${mAltitude.round()}", x(55), y(0));

    // boundary
    paintStroke.color = Colors.white;
    drawRect(x(50), y(35), x(85), y(-35), paintStroke);

    /**
     * VSI tape
     */

    paintStroke.color = Colors.white;

    //lines
    drawLine(x(90), y(5   * VSI_FIVE), x(85), y(5   * VSI_FIVE), paintStroke);
    drawLine(x(95), y(10  * VSI_FIVE), x(85), y(10  * VSI_FIVE), paintStroke);
    drawLine(x(90), y(15  * VSI_FIVE), x(85), y(15  * VSI_FIVE), paintStroke);
    drawLine(x(90), y(-5  * VSI_FIVE), x(85), y(-5  * VSI_FIVE), paintStroke);
    drawLine(x(95), y(-10 * VSI_FIVE), x(85), y(-10 * VSI_FIVE), paintStroke);
    drawLine(x(90), y(-15 * VSI_FIVE), x(85), y(-15 * VSI_FIVE), paintStroke);


    // boundary
    path.reset();
    path.moveTo(x(85), y(20 * VSI_FIVE));
    path.lineTo(x(98), y(20 * VSI_FIVE));
    path.lineTo(x(98), y(5 * VSI_FIVE));
    path.lineTo(x(85), y(0 * VSI_FIVE));
    path.lineTo(x(98), y(-5 * VSI_FIVE));
    path.lineTo(x(98), y(-20 * VSI_FIVE));
    path.lineTo(x(85), y(-20 * VSI_FIVE));
    canvas.drawPath(path, paintStroke);


    // text on VSI
    drawText("1", x(90), y(12 * VSI_FIVE));
    drawText("2", x(90), y(22 * VSI_FIVE));
    drawText("1", x(90), y(-8 * VSI_FIVE));
    drawText("2", x(90), y(-18 * VSI_FIVE));


    // value
    paintFill.color = Colors.black;

    double offs = mVsi / 100 * VSI_FIVE;
    path.reset();
    path.moveTo(x(85), y(0 * VSI_FIVE + offs));
    path.lineTo(x(92), y(2.5 * VSI_FIVE + offs));
    path.lineTo(x(98), y(2.5 * VSI_FIVE + offs));
    path.lineTo(x(98), y(-2.5 * VSI_FIVE + offs));
    path.lineTo(x(92), y(-2.5 * VSI_FIVE + offs));
    path.lineTo(x(85), y(0 * VSI_FIVE + offs));
    canvas.drawPath(path, paintFill);

    paintStroke.color = Colors.white;
    canvas.drawPath(path, paintStroke);

    // VSI hundreds
    int hvsi = ((mVsi.abs()) % 1000) ~/ 100;
    drawText(hvsi.toString(), x(90), y(0 * VSI_FIVE + offs));


    /**
     * Compass
     */

    // arrow
    paintFill.color = Colors.white;
    path.reset();
    path.moveTo(x(-5), y(-60));
    path.lineTo(x(0), y(-65));
    path.lineTo(x(5), y(-60));
    canvas.drawPath(path, paintFill);

    canvas.save();

    // half standrad rate, 9 degrees in 6 seconds
    rotate(-18, x(0), y(-95));
    drawLine(x(0), y(-60), x(0), y(-65), paintStroke);

    // standrad rate, 18 degrees in 6 seconds
    rotate(9, x(0), y(-95));
    drawLine(x(0), y(-60), x(0), y(-65), paintStroke);

    // standrad rate, 18 degrees in 6 seconds
    rotate(18, x(0), y(-95));
    drawLine(x(0), y(-60), x(0), y(-65), paintStroke);

    // half standrad rate, 9 degrees in 6 seconds
    rotate(9, x(0), y(-95));
    drawLine(x(0), y(-60), x(0), y(-65), paintStroke);

    canvas.restore();

    //draw 12, 30 degree marks.
    canvas.save();

    rotate(-mYaw, x(0), y(-95));

    double offset = -mPaintText.width / 2;

    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("N", x(0) + offset, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("3", x(0) + offset, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("6", x(0) + offset, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("E", x(0) + offset, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("12", x(0) + offset * 2, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("15", x(0) + offset * 2, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("S", x(0) + offset, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("21", x(0) + offset * 2, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("24", x(0) + offset * 2, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("W", x(0) + offset, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("30", x(0) + offset * 2, y(-75));
    rotate(30, x(0), y(-95));
    drawLine(x(0), y(-65), x(0), y(-70), paintStroke);
    drawText("33", x(0) + offset * 2, y(-75));
    rotate(30, x(0), y(-95));

    canvas.restore();

    // airplane
    paintStroke.color = Colors.white;
    drawLine(x(0), y(-105), x(0), y(-85), paintStroke);

    //draw heading
    paintFill.color = Colors.black;
    drawRect(x(-13), y(-50), x(13), y(-58), paintFill);
    drawRect(x(-13), y(-50), x(13), y(-58), paintStroke);
    drawText("${((mYaw + 360) % 360).round()}\u00B0", x(-10), y(-54),);

    // draw rate of turn arc.
    paintStroke.strokeWidth = 4;
    paintStroke.color = Colors.purpleAccent;
    r = y(-95) - y(-65);

    rect = Rect.fromLTRB(x(0) - r, y(-95) - r, x(0) + r, y(-95) + r);
    canvas.drawArc(rect, -90 * pi / 180, mTurnTrend * pi / 180, false, paintStroke);

    // CDI

    canvas.save();
    rotate((mTo - mYaw + 360) % 360, x(0), y(-95));
    //draw dots for displacement.
    paintFill.color = Colors.white;

    for(double i = 0; i < 25; i += 5) {
      drawCircle(x(-5 - i), y(-95), y(0) - y(1), paintFill);
      drawCircle(x( 5 + i), y(-95), y(0) - y(1), paintFill);
    }

    paintStroke.color = Colors.purpleAccent;
    paintFill.color = Colors.purpleAccent;
    paintStroke.strokeWidth = 2;
    drawLine(x(0), y(-115), x(0), y(-105), paintStroke); // three to break up CDI
    drawLine(x(0), y(-85), x(0), y(-80), paintStroke);
    path.reset();
    path.moveTo(x(0), y(-75));
    path.lineTo(x(-5), y(-80));
    path.lineTo(x(5), y(-80));
    canvas.drawPath(path, paintFill);
    drawLine(x(mCdi * 5), y(-105), x(mCdi * 5), y(-85), paintStroke);
    canvas.restore();


    //draw course
    paintFill.color = Colors.black;
    drawRect(x(45), y(-70), x(71), y(-78), paintFill);
    paintStroke.color = Colors.white;
    drawRect(x(45), y(-70), x(71), y(-78), paintStroke);
    drawText("${((mTo + 360) % 360).round()}\u00B0", x(48), y(-74));

    /*
     * draw VDI
     */

    // boundary
    drawRect(x(45), y(25), x(50), y(-25), paintStroke);
    drawLine(x(45), y(0), x(50), y(0), paintStroke);

    //draw bars in 10s

    paintFill.color = Colors.white;

    drawCircle(x(47.5), y(VNAV_BAR_DEGREES * 4 * VDI_DEGREE), y(0) - y(1), paintFill);
    drawCircle(x(47.5), y(VNAV_BAR_DEGREES * 2 * VDI_DEGREE), y(0) - y(1), paintFill);
    drawCircle(x(47.5), y(-VNAV_BAR_DEGREES * 2 * VDI_DEGREE), y(0) - y(1), paintFill);
    drawCircle(x(47.5), y(-VNAV_BAR_DEGREES * 4 * VDI_DEGREE), y(0) - y(1), paintFill);

    //draw VDI circle
    if(mVdi >= VNAV_HI) {
      paintFill.color = Colors.purpleAccent;
    }
    else if(mVdi <= VNAV_LOW) {
      paintFill.color = Colors.purpleAccent;
    }
    else {
      paintFill.color = Colors.cyan;
    }

    double val = 3 - mVdi;
    drawCircle(x(47.5), y(val * VDI_DEGREE), y(0) - y(1), paintFill);

    drawText("G", x(44), y(28));

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }



}