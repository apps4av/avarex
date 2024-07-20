class UnitConversion {

  UnitConversion(String unit) {
    // default for knots
    if(unit == "Imperial") {
      mTo = 0.000621371;
      toM = 1609.34;
      mpsTo = 2.23694;
      toMps = 0.44704;
      knotsTo = 1.15078;
    }
  }

  // default is for knots and feet for maritime units

  // for vertical distance
  double mToF = 3.28084;
  double fToM = 0.3048;

  // for horizontal distance
  double mTo = 0.000539957;
  double toM = 1851.9993;

  // for speed
  double mpsTo = 1.94384; // kph, knot, mile/hr
  double toMps = 0.514446;

  // knots for wind.
  double knotsTo = 1;

}