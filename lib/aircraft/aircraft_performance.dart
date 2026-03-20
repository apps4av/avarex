import 'dart:convert';
import 'dart:math';
import 'dart:ui';

class Performance3DEntry {
  final double altitude;
  final double temp;
  final double weight;
  final double value;

  const Performance3DEntry({
    required this.altitude,
    required this.temp,
    required this.weight,
    required this.value,
  });

  Map<String, dynamic> toMap() => {
    'altitude': altitude,
    'temp': temp,
    'weight': weight,
    'value': value,
  };

  factory Performance3DEntry.fromMap(Map<String, dynamic> map) => Performance3DEntry(
    altitude: (map['altitude'] ?? 0).toDouble(),
    temp: (map['temp'] ?? 15).toDouble(),
    weight: (map['weight'] ?? 2400).toDouble(),
    value: (map['value'] ?? 0).toDouble(),
  );
}

class Cruise3DEntry {
  final double altitude;
  final double temp;
  final double powerPercent;
  final double ktas;
  final double gph;

  const Cruise3DEntry({
    required this.altitude,
    required this.temp,
    required this.powerPercent,
    required this.ktas,
    required this.gph,
  });

  Map<String, dynamic> toMap() => {
    'altitude': altitude,
    'temp': temp,
    'powerPercent': powerPercent,
    'ktas': ktas,
    'gph': gph,
  };

  factory Cruise3DEntry.fromMap(Map<String, dynamic> map) => Cruise3DEntry(
    altitude: (map['altitude'] ?? 0).toDouble(),
    temp: (map['temp'] ?? 0).toDouble(),
    powerPercent: (map['powerPercent'] ?? 75).toDouble(),
    ktas: (map['ktas'] ?? 120).toDouble(),
    gph: (map['gph'] ?? 10).toDouble(),
  );
}

class Interpolator3D {
  static double interpolatePerformance(List<Performance3DEntry> entries, double alt, double temp, double weight) {
    if (entries.isEmpty) return 0;
    if (entries.length == 1) return entries.first.value;

    Performance3DEntry? exact = entries.cast<Performance3DEntry?>().firstWhere(
      (e) => e!.altitude == alt && e.temp == temp && e.weight == weight,
      orElse: () => null,
    );
    if (exact != null) return exact.value;

    List<Performance3DEntry> sameTempWeight = entries.where((e) => e.temp == temp && e.weight == weight).toList();
    if (sameTempWeight.length >= 2) {
      sameTempWeight.sort((a, b) => a.altitude.compareTo(b.altitude));
      double? result = _interpolateAlongDimension(sameTempWeight.map((e) => _DimValue(e.altitude, e.value)).toList(), alt);
      if (result != null) return result;
    }

    List<Performance3DEntry> sameAltWeight = entries.where((e) => e.altitude == alt && e.weight == weight).toList();
    if (sameAltWeight.length >= 2) {
      sameAltWeight.sort((a, b) => a.temp.compareTo(b.temp));
      double? result = _interpolateAlongDimension(sameAltWeight.map((e) => _DimValue(e.temp, e.value)).toList(), temp);
      if (result != null) return result;
    }

    List<Performance3DEntry> sameAltTemp = entries.where((e) => e.altitude == alt && e.temp == temp).toList();
    if (sameAltTemp.length >= 2) {
      sameAltTemp.sort((a, b) => a.weight.compareTo(b.weight));
      double? result = _interpolateAlongDimension(sameAltTemp.map((e) => _DimValue(e.weight, e.value)).toList(), weight);
      if (result != null) return result;
    }

    return _inverseDistanceWeighted(entries, alt, temp, weight);
  }

  static double? _interpolateAlongDimension(List<_DimValue> sorted, double target) {
    for (int i = 0; i < sorted.length - 1; i++) {
      if (target >= sorted[i].dim && target <= sorted[i + 1].dim) {
        double frac = (sorted[i + 1].dim == sorted[i].dim) ? 0 :
            (target - sorted[i].dim) / (sorted[i + 1].dim - sorted[i].dim);
        return sorted[i].value + (sorted[i + 1].value - sorted[i].value) * frac;
      }
    }
    if (target < sorted.first.dim) return sorted.first.value;
    if (target > sorted.last.dim) return sorted.last.value;
    return null;
  }

  static double _inverseDistanceWeighted(List<Performance3DEntry> entries, double alt, double temp, double weight) {
    double totalW = 0;
    double weightedSum = 0;
    for (var e in entries) {
      double altDist = (e.altitude - alt).abs() / 1000;
      double tempDist = (e.temp - temp).abs() / 10;
      double weightDist = (e.weight - weight).abs() / 500;
      double dist = sqrt(altDist * altDist + tempDist * tempDist + weightDist * weightDist);
      if (dist < 0.001) dist = 0.001;
      double w = 1 / (dist * dist);
      weightedSum += e.value * w;
      totalW += w;
    }
    return totalW > 0 ? weightedSum / totalW : entries.first.value;
  }

  static CruiseResult interpolateCruise(List<Cruise3DEntry> entries, double alt, double temp, double power) {
    if (entries.isEmpty) return CruiseResult(ktas: 0, gph: 0);
    if (entries.length == 1) return CruiseResult(ktas: entries.first.ktas, gph: entries.first.gph);

    Cruise3DEntry? exact = entries.cast<Cruise3DEntry?>().firstWhere(
      (e) => e!.altitude == alt && e.temp == temp && e.powerPercent == power,
      orElse: () => null,
    );
    if (exact != null) return CruiseResult(ktas: exact.ktas, gph: exact.gph);

    double totalW = 0;
    double ktasSum = 0;
    double gphSum = 0;
    for (var e in entries) {
      double altDist = (e.altitude - alt).abs() / 1000;
      double tempDist = (e.temp - temp).abs() / 10;
      double powerDist = (e.powerPercent - power).abs() / 10;
      double dist = sqrt(altDist * altDist + tempDist * tempDist + powerDist * powerDist);
      if (dist < 0.001) dist = 0.001;
      double w = 1 / (dist * dist);
      ktasSum += e.ktas * w;
      gphSum += e.gph * w;
      totalW += w;
    }
    if (totalW > 0) {
      return CruiseResult(ktas: ktasSum / totalW, gph: gphSum / totalW);
    }
    return CruiseResult(ktas: entries.first.ktas, gph: entries.first.gph);
  }
}

class _DimValue {
  final double dim;
  final double value;
  _DimValue(this.dim, this.value);
}

class PerformanceTable {
  final List<double> pressureAltitudes;
  final List<double> temperatures;
  final List<List<double>> values;

  const PerformanceTable({
    required this.pressureAltitudes,
    required this.temperatures,
    required this.values,
  });

  double interpolate(double pressureAlt, double tempC) {
    int paLowIdx = 0;
    int paHighIdx = 0;
    for (int i = 0; i < pressureAltitudes.length - 1; i++) {
      if (pressureAlt >= pressureAltitudes[i] && pressureAlt <= pressureAltitudes[i + 1]) {
        paLowIdx = i;
        paHighIdx = i + 1;
        break;
      }
      if (pressureAlt < pressureAltitudes[0]) {
        paLowIdx = 0;
        paHighIdx = 0;
        break;
      }
      if (pressureAlt > pressureAltitudes.last) {
        paLowIdx = pressureAltitudes.length - 1;
        paHighIdx = pressureAltitudes.length - 1;
        break;
      }
    }

    int tempLowIdx = 0;
    int tempHighIdx = 0;
    for (int i = 0; i < temperatures.length - 1; i++) {
      if (tempC >= temperatures[i] && tempC <= temperatures[i + 1]) {
        tempLowIdx = i;
        tempHighIdx = i + 1;
        break;
      }
      if (tempC < temperatures[0]) {
        tempLowIdx = 0;
        tempHighIdx = 0;
        break;
      }
      if (tempC > temperatures.last) {
        tempLowIdx = temperatures.length - 1;
        tempHighIdx = temperatures.length - 1;
        break;
      }
    }

    double paLow = pressureAltitudes[paLowIdx];
    double paHigh = pressureAltitudes[paHighIdx];
    double tempLow = temperatures[tempLowIdx];
    double tempHigh = temperatures[tempHighIdx];

    double v11 = values[paLowIdx][tempLowIdx];
    double v12 = values[paLowIdx][tempHighIdx];
    double v21 = values[paHighIdx][tempLowIdx];
    double v22 = values[paHighIdx][tempHighIdx];

    double paFrac = (paHigh == paLow) ? 0 : (pressureAlt - paLow) / (paHigh - paLow);
    double tempFrac = (tempHigh == tempLow) ? 0 : (tempC - tempLow) / (tempHigh - tempLow);

    double v1 = v11 + (v12 - v11) * tempFrac;
    double v2 = v21 + (v22 - v21) * tempFrac;
    
    return v1 + (v2 - v1) * paFrac;
  }

  Map<String, dynamic> toMap() {
    return {
      'pressureAltitudes': pressureAltitudes,
      'temperatures': temperatures,
      'values': values,
    };
  }

  factory PerformanceTable.fromMap(Map<String, dynamic> map) {
    return PerformanceTable(
      pressureAltitudes: List<double>.from(map['pressureAltitudes']),
      temperatures: List<double>.from(map['temperatures']),
      values: (map['values'] as List).map((row) => List<double>.from(row)).toList(),
    );
  }
}

class WeightAdjustedTable {
  final List<double> weights;
  final List<PerformanceTable> tables;

  const WeightAdjustedTable({
    required this.weights,
    required this.tables,
  });

  double interpolate(double pressureAlt, double tempC, double weight) {
    int wLowIdx = 0;
    int wHighIdx = 0;
    for (int i = 0; i < weights.length - 1; i++) {
      if (weight >= weights[i] && weight <= weights[i + 1]) {
        wLowIdx = i;
        wHighIdx = i + 1;
        break;
      }
      if (weight < weights[0]) {
        wLowIdx = 0;
        wHighIdx = 0;
        break;
      }
      if (weight > weights.last) {
        wLowIdx = weights.length - 1;
        wHighIdx = weights.length - 1;
        break;
      }
    }

    double wLow = weights[wLowIdx];
    double wHigh = weights[wHighIdx];
    
    double v1 = tables[wLowIdx].interpolate(pressureAlt, tempC);
    double v2 = tables[wHighIdx].interpolate(pressureAlt, tempC);
    
    double wFrac = (wHigh == wLow) ? 0 : (weight - wLow) / (wHigh - wLow);
    
    return v1 + (v2 - v1) * wFrac;
  }
}

class CruiseTableEntry {
  final int altitude;
  final int temp;
  final int rpm;
  final int percentPower;
  final double ktas;
  final double gph;

  const CruiseTableEntry({
    required this.altitude,
    this.temp = 0,
    required this.rpm,
    required this.percentPower,
    required this.ktas,
    required this.gph,
  });

  Map<String, dynamic> toMap() {
    return {
      'altitude': altitude,
      'temp': temp,
      'rpm': rpm,
      'percentPower': percentPower,
      'ktas': ktas,
      'gph': gph,
    };
  }

  factory CruiseTableEntry.fromMap(Map<String, dynamic> map) {
    return CruiseTableEntry(
      altitude: map['altitude'],
      temp: map['temp'] ?? 0,
      rpm: map['rpm'],
      percentPower: map['percentPower'],
      ktas: (map['ktas'] as num).toDouble(),
      gph: (map['gph'] as num).toDouble(),
    );
  }
}

class CruisePerformanceTable {
  final List<CruiseTableEntry> entries;

  const CruisePerformanceTable({required this.entries});

  CruiseResult interpolate(int altitude, int percentPower, [int temp = 0]) {
    if (entries.isEmpty) {
      return CruiseResult(ktas: 0, gph: 0, percentPower: percentPower);
    }

    Set<int> temps = entries.map((e) => e.temp).toSet();
    bool hasMultipleTemps = temps.length > 1;

    if (!hasMultipleTemps) {
      return _interpolateAtAltitudeAndPower(altitude, percentPower);
    }

    List<int> sortedTemps = temps.toList()..sort();
    int tempLow = sortedTemps.first;
    int tempHigh = sortedTemps.last;

    for (int i = 0; i < sortedTemps.length - 1; i++) {
      if (temp >= sortedTemps[i] && temp <= sortedTemps[i + 1]) {
        tempLow = sortedTemps[i];
        tempHigh = sortedTemps[i + 1];
        break;
      }
    }

    if (temp < sortedTemps.first) {
      tempLow = sortedTemps.first;
      tempHigh = sortedTemps.first;
    }
    if (temp > sortedTemps.last) {
      tempLow = sortedTemps.last;
      tempHigh = sortedTemps.last;
    }

    CruiseResult lowResult = _interpolateAtAltitudePowerTemp(altitude, percentPower, tempLow);
    CruiseResult highResult = _interpolateAtAltitudePowerTemp(altitude, percentPower, tempHigh);

    double tempFrac = (tempHigh == tempLow) ? 0 : (temp - tempLow) / (tempHigh - tempLow);

    return CruiseResult(
      ktas: lowResult.ktas + (highResult.ktas - lowResult.ktas) * tempFrac,
      gph: lowResult.gph + (highResult.gph - lowResult.gph) * tempFrac,
      percentPower: percentPower,
    );
  }

  CruiseResult _interpolateAtAltitudeAndPower(int altitude, int percentPower) {
    List<int> altitudes = entries.map((e) => e.altitude).toSet().toList()..sort();
    
    if (altitudes.isEmpty) {
      return CruiseResult(ktas: 0, gph: 0, percentPower: percentPower);
    }

    int altLow = altitudes.first;
    int altHigh = altitudes.last;

    for (int i = 0; i < altitudes.length - 1; i++) {
      if (altitude >= altitudes[i] && altitude <= altitudes[i + 1]) {
        altLow = altitudes[i];
        altHigh = altitudes[i + 1];
        break;
      }
    }

    if (altitude < altitudes.first) {
      altLow = altitudes.first;
      altHigh = altitudes.first;
    }
    if (altitude > altitudes.last) {
      altLow = altitudes.last;
      altHigh = altitudes.last;
    }

    CruiseResult lowResult = _interpolateAtPower(altLow, percentPower);
    CruiseResult highResult = _interpolateAtPower(altHigh, percentPower);

    double altFrac = (altHigh == altLow) ? 0 : (altitude - altLow) / (altHigh - altLow);

    return CruiseResult(
      ktas: lowResult.ktas + (highResult.ktas - lowResult.ktas) * altFrac,
      gph: lowResult.gph + (highResult.gph - lowResult.gph) * altFrac,
      percentPower: percentPower,
    );
  }

  CruiseResult _interpolateAtAltitudePowerTemp(int altitude, int percentPower, int temp) {
    List<CruiseTableEntry> atTemp = entries.where((e) => e.temp == temp).toList();
    if (atTemp.isEmpty) {
      return _interpolateAtAltitudeAndPower(altitude, percentPower);
    }

    List<int> altitudes = atTemp.map((e) => e.altitude).toSet().toList()..sort();
    
    int altLow = altitudes.first;
    int altHigh = altitudes.last;

    for (int i = 0; i < altitudes.length - 1; i++) {
      if (altitude >= altitudes[i] && altitude <= altitudes[i + 1]) {
        altLow = altitudes[i];
        altHigh = altitudes[i + 1];
        break;
      }
    }

    if (altitude < altitudes.first) {
      altLow = altitudes.first;
      altHigh = altitudes.first;
    }
    if (altitude > altitudes.last) {
      altLow = altitudes.last;
      altHigh = altitudes.last;
    }

    CruiseResult lowResult = _interpolateAtPowerAndTemp(altLow, percentPower, temp);
    CruiseResult highResult = _interpolateAtPowerAndTemp(altHigh, percentPower, temp);

    double altFrac = (altHigh == altLow) ? 0 : (altitude - altLow) / (altHigh - altLow);

    return CruiseResult(
      ktas: lowResult.ktas + (highResult.ktas - lowResult.ktas) * altFrac,
      gph: lowResult.gph + (highResult.gph - lowResult.gph) * altFrac,
      percentPower: percentPower,
    );
  }

  CruiseResult _interpolateAtPower(int altitude, int percentPower) {
    List<CruiseTableEntry> atAlt = entries.where((e) => e.altitude == altitude).toList();
    if (atAlt.isEmpty) {
      return CruiseResult(ktas: 0, gph: 0, percentPower: percentPower);
    }

    atAlt.sort((a, b) => a.percentPower.compareTo(b.percentPower));

    CruiseTableEntry? low;
    CruiseTableEntry? high;

    for (int i = 0; i < atAlt.length - 1; i++) {
      if (percentPower >= atAlt[i].percentPower && percentPower <= atAlt[i + 1].percentPower) {
        low = atAlt[i];
        high = atAlt[i + 1];
        break;
      }
    }

    if (low == null || high == null) {
      if (percentPower <= atAlt.first.percentPower) {
        low = atAlt.first;
        high = atAlt.first;
      } else {
        low = atAlt.last;
        high = atAlt.last;
      }
    }

    double frac = (high.percentPower == low.percentPower)
        ? 0
        : (percentPower - low.percentPower) / (high.percentPower - low.percentPower);

    return CruiseResult(
      ktas: low.ktas + (high.ktas - low.ktas) * frac,
      gph: low.gph + (high.gph - low.gph) * frac,
      percentPower: percentPower,
    );
  }

  CruiseResult _interpolateAtPowerAndTemp(int altitude, int percentPower, int temp) {
    List<CruiseTableEntry> atAltTemp = entries.where((e) => e.altitude == altitude && e.temp == temp).toList();
    if (atAltTemp.isEmpty) {
      return _interpolateAtPower(altitude, percentPower);
    }

    atAltTemp.sort((a, b) => a.percentPower.compareTo(b.percentPower));

    CruiseTableEntry? low;
    CruiseTableEntry? high;

    for (int i = 0; i < atAltTemp.length - 1; i++) {
      if (percentPower >= atAltTemp[i].percentPower && percentPower <= atAltTemp[i + 1].percentPower) {
        low = atAltTemp[i];
        high = atAltTemp[i + 1];
        break;
      }
    }

    if (low == null || high == null) {
      if (percentPower <= atAltTemp.first.percentPower) {
        low = atAltTemp.first;
        high = atAltTemp.first;
      } else {
        low = atAltTemp.last;
        high = atAltTemp.last;
      }
    }

    double frac = (high.percentPower == low.percentPower)
        ? 0
        : (percentPower - low.percentPower) / (high.percentPower - low.percentPower);

    return CruiseResult(
      ktas: low.ktas + (high.ktas - low.ktas) * frac,
      gph: low.gph + (high.gph - low.gph) * frac,
      percentPower: percentPower,
    );
  }
}

class CruiseResult {
  final double ktas;
  final double gph;
  final int percentPower;

  CruiseResult({required this.ktas, required this.gph, this.percentPower = 0});
}

class AircraftPerformanceData {
  final String name;
  final String icaoType;
  
  final double maxGrossWeight;
  final double usableFuel;
  final double emptyWeight;
  
  final PerformanceTable takeoffGroundRoll;
  final PerformanceTable takeoffOver50ft;
  final PerformanceTable landingGroundRoll;
  final PerformanceTable landingOver50ft;
  final CruisePerformanceTable cruiseTable;
  
  final List<Performance3DEntry>? rawTakeoffRollEntries;
  final List<Performance3DEntry>? rawTakeoff50ftEntries;
  final List<Performance3DEntry>? rawLandingRollEntries;
  final List<Performance3DEntry>? rawLanding50ftEntries;
  final List<Cruise3DEntry>? rawCruiseEntries;
  
  final double takeoffHeadwindPct;
  final double takeoffTailwindPct;
  final double takeoffSoftFieldPct;
  final double landingHeadwindPct;
  final double landingTailwindPct;
  final double landingSoftFieldPct;

  const AircraftPerformanceData({
    required this.name,
    required this.icaoType,
    required this.maxGrossWeight,
    required this.usableFuel,
    required this.emptyWeight,
    required this.takeoffGroundRoll,
    required this.takeoffOver50ft,
    required this.landingGroundRoll,
    required this.landingOver50ft,
    required this.cruiseTable,
    this.rawTakeoffRollEntries,
    this.rawTakeoff50ftEntries,
    this.rawLandingRollEntries,
    this.rawLanding50ftEntries,
    this.rawCruiseEntries,
    this.takeoffHeadwindPct = 1.5,
    this.takeoffTailwindPct = 10.0,
    this.takeoffSoftFieldPct = 15.0,
    this.landingHeadwindPct = 1.5,
    this.landingTailwindPct = 10.0,
    this.landingSoftFieldPct = 20.0,
  });

  bool get hasRawEntries => rawTakeoffRollEntries != null || rawCruiseEntries != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AircraftPerformanceData &&
        other.name == name &&
        other.icaoType == icaoType &&
        other.maxGrossWeight == maxGrossWeight;
  }

  @override
  int get hashCode => Object.hash(name, icaoType, maxGrossWeight);

  double getTakeoffGroundRoll(double pressureAlt, double tempC, double weight, double headwind, bool softField) {
    double baseRoll;
    
    if (rawTakeoffRollEntries != null && rawTakeoffRollEntries!.isNotEmpty) {
      baseRoll = Interpolator3D.interpolatePerformance(rawTakeoffRollEntries!, pressureAlt, tempC, weight);
    } else {
      baseRoll = takeoffGroundRoll.interpolate(pressureAlt, tempC);
      double weightFactor = pow(weight / maxGrossWeight, 2).toDouble();
      baseRoll *= weightFactor;
    }
    
    if (headwind > 0) {
      baseRoll *= (1 - headwind * takeoffHeadwindPct / 100);
    } else if (headwind < 0) {
      baseRoll *= (1 + headwind.abs() * takeoffTailwindPct / 100);
    }
    
    if (softField) {
      baseRoll *= (1 + takeoffSoftFieldPct / 100);
    }
    
    return baseRoll.clamp(100, 10000);
  }

  double getTakeoffOver50ft(double pressureAlt, double tempC, double weight, double headwind, bool softField) {
    double baseDist;
    
    if (rawTakeoff50ftEntries != null && rawTakeoff50ftEntries!.isNotEmpty) {
      baseDist = Interpolator3D.interpolatePerformance(rawTakeoff50ftEntries!, pressureAlt, tempC, weight);
    } else {
      baseDist = takeoffOver50ft.interpolate(pressureAlt, tempC);
      double weightFactor = pow(weight / maxGrossWeight, 2).toDouble();
      baseDist *= weightFactor;
    }
    
    if (headwind > 0) {
      baseDist *= (1 - headwind * takeoffHeadwindPct / 100);
    } else if (headwind < 0) {
      baseDist *= (1 + headwind.abs() * takeoffTailwindPct / 100);
    }
    
    if (softField) {
      baseDist *= (1 + takeoffSoftFieldPct / 100);
    }
    
    return baseDist.clamp(200, 15000);
  }

  double getLandingGroundRoll(double pressureAlt, double tempC, double weight, double headwind, bool softField) {
    double baseRoll;
    
    if (rawLandingRollEntries != null && rawLandingRollEntries!.isNotEmpty) {
      baseRoll = Interpolator3D.interpolatePerformance(rawLandingRollEntries!, pressureAlt, tempC, weight);
    } else {
      baseRoll = landingGroundRoll.interpolate(pressureAlt, tempC);
      double weightFactor = weight / maxGrossWeight;
      baseRoll *= weightFactor;
    }
    
    if (headwind > 0) {
      baseRoll *= (1 - headwind * landingHeadwindPct / 100);
    } else if (headwind < 0) {
      baseRoll *= (1 + headwind.abs() * landingTailwindPct / 100);
    }
    
    if (softField) {
      baseRoll *= (1 + landingSoftFieldPct / 100);
    }
    
    return baseRoll.clamp(100, 8000);
  }

  double getLandingOver50ft(double pressureAlt, double tempC, double weight, double headwind, bool softField) {
    double baseDist;
    
    if (rawLanding50ftEntries != null && rawLanding50ftEntries!.isNotEmpty) {
      baseDist = Interpolator3D.interpolatePerformance(rawLanding50ftEntries!, pressureAlt, tempC, weight);
    } else {
      baseDist = landingOver50ft.interpolate(pressureAlt, tempC);
      double weightFactor = weight / maxGrossWeight;
      baseDist *= weightFactor;
    }
    
    if (headwind > 0) {
      baseDist *= (1 - headwind * landingHeadwindPct / 100);
    } else if (headwind < 0) {
      baseDist *= (1 + headwind.abs() * landingTailwindPct / 100);
    }
    
    if (softField) {
      baseDist *= (1 + landingSoftFieldPct / 100);
    }
    
    return baseDist.clamp(200, 12000);
  }

  CruiseResult getCruisePerformance(int altitude, int percentPower, [int temp = 0]) {
    if (rawCruiseEntries != null && rawCruiseEntries!.isNotEmpty) {
      return Interpolator3D.interpolateCruise(
        rawCruiseEntries!, 
        altitude.toDouble(), 
        temp.toDouble(), 
        percentPower.toDouble()
      );
    }
    return cruiseTable.interpolate(altitude, percentPower, temp);
  }
}

class PerformanceCalculator {
  static double calculateDensityAltitude(double pressureAltitude, double tempCelsius) {
    double stdTemp = 15 - (pressureAltitude / 1000) * 1.98;
    double isaDeviation = tempCelsius - stdTemp;
    return pressureAltitude + (120 * isaDeviation);
  }

  static double calculatePressureAltitude(double fieldElevation, double altimeterSetting) {
    return fieldElevation + (29.92 - altimeterSetting) * 1000;
  }
}

class FuelCalculation {
  final double tripFuel;
  final double reserveFuel;
  final double taxiFuel;
  final double totalFuel;
  final Duration flightTime;

  FuelCalculation({
    required this.tripFuel,
    required this.reserveFuel,
    required this.taxiFuel,
    required this.totalFuel,
    required this.flightTime,
  });

  static FuelCalculation calculate({
    required double distance,
    required double groundSpeed,
    required double fuelFlowGph,
    required double reserveMinutes,
    double taxiFuel = 1.0,
  }) {
    double flightTimeHours = distance / groundSpeed;
    double tripFuel = flightTimeHours * fuelFlowGph;
    double reserveFuel = (reserveMinutes / 60) * fuelFlowGph;
    double totalFuel = tripFuel + reserveFuel + taxiFuel;
    
    return FuelCalculation(
      tripFuel: tripFuel,
      reserveFuel: reserveFuel,
      taxiFuel: taxiFuel,
      totalFuel: totalFuel,
      flightTime: Duration(minutes: (flightTimeHours * 60).round()),
    );
  }
}

class CommonAircraftData {
  
  // Cessna 172S POH Performance Data (Skyhawk SP, 180hp, Max Gross 2550 lbs)
  static final cessna172sp = AircraftPerformanceData(
    name: 'Cessna 172S Skyhawk SP',
    icaoType: 'C172',
    maxGrossWeight: 2550,
    usableFuel: 53,
    emptyWeight: 1663,
    takeoffGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [695, 750, 805, 865, 935],     // SL
        [765, 825, 890, 960, 1035],    // 1000
        [845, 915, 990, 1070, 1155],   // 2000
        [935, 1015, 1100, 1195, 1295], // 3000
        [1040, 1130, 1230, 1340, 1460],// 4000
        [1160, 1270, 1385, 1515, 1660],// 5000
        [1305, 1435, 1580, 1740, 1920],// 6000
        [1485, 1645, 1825, 2030, 2265],// 7000
        [1715, 1920, 2160, 2435, 2760],// 8000
      ],
    ),
    takeoffOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1210, 1300, 1400, 1510, 1630],  // SL
        [1340, 1445, 1560, 1685, 1825],  // 1000
        [1490, 1615, 1750, 1900, 2065],  // 2000
        [1670, 1815, 1980, 2160, 2365],  // 3000
        [1880, 2055, 2255, 2480, 2735],  // 4000
        [2135, 2350, 2600, 2880, 3200],  // 5000
        [2455, 2725, 3040, 3400, 3820],  // 6000
        [2870, 3220, 3630, 4110, 4685],  // 7000
        [3435, 3915, 4490, 5175, 6010],  // 8000
      ],
    ),
    landingGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [545, 550, 555, 560, 565],   // SL
        [565, 570, 575, 580, 590],   // 1000
        [585, 590, 600, 605, 615],   // 2000
        [605, 615, 620, 630, 640],   // 3000
        [630, 640, 645, 655, 665],   // 4000
        [655, 665, 675, 685, 695],   // 5000
        [685, 695, 705, 715, 725],   // 6000
        [715, 725, 735, 750, 760],   // 7000
        [750, 760, 775, 785, 800],   // 8000
      ],
    ),
    landingOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1280, 1290, 1300, 1315, 1330],  // SL
        [1320, 1335, 1350, 1365, 1385],  // 1000
        [1365, 1385, 1400, 1420, 1440],  // 2000
        [1415, 1435, 1455, 1475, 1500],  // 3000
        [1470, 1490, 1515, 1540, 1565],  // 4000
        [1530, 1555, 1580, 1605, 1635],  // 5000
        [1595, 1620, 1650, 1680, 1710],  // 6000
        [1665, 1695, 1725, 1760, 1795],  // 7000
        [1745, 1780, 1815, 1850, 1890],  // 8000
      ],
    ),
    cruiseTable: CruisePerformanceTable(entries: [
      // 4000 ft
      CruiseTableEntry(altitude: 4000, rpm: 2500, percentPower: 78, ktas: 126, gph: 10.6),
      CruiseTableEntry(altitude: 4000, rpm: 2400, percentPower: 72, ktas: 122, gph: 9.6),
      CruiseTableEntry(altitude: 4000, rpm: 2300, percentPower: 66, ktas: 117, gph: 8.7),
      CruiseTableEntry(altitude: 4000, rpm: 2200, percentPower: 60, ktas: 112, gph: 7.9),
      CruiseTableEntry(altitude: 4000, rpm: 2100, percentPower: 55, ktas: 106, gph: 7.2),
      // 6000 ft
      CruiseTableEntry(altitude: 6000, rpm: 2500, percentPower: 75, ktas: 125, gph: 10.1),
      CruiseTableEntry(altitude: 6000, rpm: 2400, percentPower: 69, ktas: 121, gph: 9.2),
      CruiseTableEntry(altitude: 6000, rpm: 2300, percentPower: 63, ktas: 116, gph: 8.3),
      CruiseTableEntry(altitude: 6000, rpm: 2200, percentPower: 57, ktas: 110, gph: 7.5),
      CruiseTableEntry(altitude: 6000, rpm: 2100, percentPower: 52, ktas: 104, gph: 6.9),
      // 8000 ft
      CruiseTableEntry(altitude: 8000, rpm: 2500, percentPower: 72, ktas: 124, gph: 9.6),
      CruiseTableEntry(altitude: 8000, rpm: 2400, percentPower: 66, ktas: 120, gph: 8.7),
      CruiseTableEntry(altitude: 8000, rpm: 2300, percentPower: 60, ktas: 115, gph: 7.9),
      CruiseTableEntry(altitude: 8000, rpm: 2200, percentPower: 55, ktas: 109, gph: 7.2),
      CruiseTableEntry(altitude: 8000, rpm: 2100, percentPower: 50, ktas: 103, gph: 6.5),
      // 10000 ft
      CruiseTableEntry(altitude: 10000, rpm: 2500, percentPower: 68, ktas: 123, gph: 9.1),
      CruiseTableEntry(altitude: 10000, rpm: 2400, percentPower: 63, ktas: 118, gph: 8.3),
      CruiseTableEntry(altitude: 10000, rpm: 2300, percentPower: 57, ktas: 113, gph: 7.5),
      CruiseTableEntry(altitude: 10000, rpm: 2200, percentPower: 52, ktas: 107, gph: 6.8),
      CruiseTableEntry(altitude: 10000, rpm: 2100, percentPower: 47, ktas: 100, gph: 6.2),
      // 12000 ft
      CruiseTableEntry(altitude: 12000, rpm: 2500, percentPower: 65, ktas: 121, gph: 8.6),
      CruiseTableEntry(altitude: 12000, rpm: 2400, percentPower: 60, ktas: 117, gph: 7.9),
      CruiseTableEntry(altitude: 12000, rpm: 2300, percentPower: 55, ktas: 111, gph: 7.1),
      CruiseTableEntry(altitude: 12000, rpm: 2200, percentPower: 50, ktas: 105, gph: 6.5),
      CruiseTableEntry(altitude: 12000, rpm: 2100, percentPower: 45, ktas: 98, gph: 5.9),
    ]),
  );

  // Cessna 182T POH Performance Data (Skylane, 230hp, Max Gross 3100 lbs)
  static final cessna182t = AircraftPerformanceData(
    name: 'Cessna 182T Skylane',
    icaoType: 'C182',
    maxGrossWeight: 3100,
    usableFuel: 87,
    emptyWeight: 1970,
    takeoffGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [625, 675, 730, 790, 855],    // SL
        [690, 745, 810, 880, 955],    // 1000
        [765, 830, 905, 985, 1075],   // 2000
        [850, 930, 1015, 1110, 1215], // 3000
        [950, 1040, 1145, 1260, 1385],// 4000
        [1070, 1180, 1305, 1445, 1600],// 5000
        [1215, 1350, 1505, 1680, 1880],// 6000
        [1400, 1570, 1770, 1995, 2260],// 7000
        [1650, 1875, 2140, 2450, 2815],// 8000
      ],
    ),
    takeoffOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1145, 1235, 1335, 1445, 1565],  // SL
        [1275, 1380, 1495, 1625, 1765],  // 1000
        [1425, 1550, 1690, 1845, 2015],  // 2000
        [1600, 1750, 1920, 2110, 2325],  // 3000
        [1810, 1995, 2205, 2440, 2710],  // 4000
        [2065, 2295, 2560, 2860, 3205],  // 5000
        [2385, 2680, 3020, 3415, 3875],  // 6000
        [2810, 3195, 3655, 4195, 4835],  // 7000
        [3400, 3935, 4580, 5350, 6280],  // 8000
      ],
    ),
    landingGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [560, 565, 570, 580, 585],   // SL
        [580, 590, 595, 605, 615],   // 1000
        [605, 615, 625, 635, 645],   // 2000
        [635, 645, 655, 665, 680],   // 3000
        [665, 675, 690, 700, 715],   // 4000
        [700, 710, 725, 740, 755],   // 5000
        [735, 750, 765, 780, 795],   // 6000
        [775, 790, 805, 825, 840],   // 7000
        [820, 835, 855, 875, 895],   // 8000
      ],
    ),
    landingOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1320, 1335, 1350, 1370, 1390],  // SL
        [1370, 1390, 1410, 1430, 1455],  // 1000
        [1430, 1450, 1475, 1500, 1525],  // 2000
        [1490, 1515, 1545, 1575, 1605],  // 3000
        [1560, 1590, 1620, 1655, 1690],  // 4000
        [1640, 1670, 1705, 1745, 1785],  // 5000
        [1720, 1760, 1800, 1840, 1885],  // 6000
        [1815, 1855, 1900, 1950, 2000],  // 7000
        [1920, 1965, 2015, 2070, 2125],  // 8000
      ],
    ),
    cruiseTable: CruisePerformanceTable(entries: [
      // 4000 ft
      CruiseTableEntry(altitude: 4000, rpm: 2400, percentPower: 82, ktas: 150, gph: 14.4),
      CruiseTableEntry(altitude: 4000, rpm: 2300, percentPower: 75, ktas: 145, gph: 13.0),
      CruiseTableEntry(altitude: 4000, rpm: 2200, percentPower: 68, ktas: 139, gph: 11.6),
      CruiseTableEntry(altitude: 4000, rpm: 2100, percentPower: 61, ktas: 132, gph: 10.4),
      CruiseTableEntry(altitude: 4000, rpm: 2000, percentPower: 55, ktas: 124, gph: 9.4),
      // 6000 ft
      CruiseTableEntry(altitude: 6000, rpm: 2400, percentPower: 78, ktas: 150, gph: 13.7),
      CruiseTableEntry(altitude: 6000, rpm: 2300, percentPower: 71, ktas: 144, gph: 12.3),
      CruiseTableEntry(altitude: 6000, rpm: 2200, percentPower: 65, ktas: 138, gph: 11.0),
      CruiseTableEntry(altitude: 6000, rpm: 2100, percentPower: 58, ktas: 130, gph: 9.8),
      CruiseTableEntry(altitude: 6000, rpm: 2000, percentPower: 52, ktas: 122, gph: 8.8),
      // 8000 ft
      CruiseTableEntry(altitude: 8000, rpm: 2400, percentPower: 75, ktas: 149, gph: 13.0),
      CruiseTableEntry(altitude: 8000, rpm: 2300, percentPower: 68, ktas: 143, gph: 11.7),
      CruiseTableEntry(altitude: 8000, rpm: 2200, percentPower: 61, ktas: 136, gph: 10.4),
      CruiseTableEntry(altitude: 8000, rpm: 2100, percentPower: 55, ktas: 128, gph: 9.3),
      CruiseTableEntry(altitude: 8000, rpm: 2000, percentPower: 49, ktas: 119, gph: 8.3),
      // 10000 ft
      CruiseTableEntry(altitude: 10000, rpm: 2400, percentPower: 71, ktas: 148, gph: 12.4),
      CruiseTableEntry(altitude: 10000, rpm: 2300, percentPower: 64, ktas: 141, gph: 11.1),
      CruiseTableEntry(altitude: 10000, rpm: 2200, percentPower: 58, ktas: 133, gph: 9.9),
      CruiseTableEntry(altitude: 10000, rpm: 2100, percentPower: 52, ktas: 125, gph: 8.8),
      CruiseTableEntry(altitude: 10000, rpm: 2000, percentPower: 46, ktas: 116, gph: 7.8),
      // 12000 ft
      CruiseTableEntry(altitude: 12000, rpm: 2400, percentPower: 67, ktas: 146, gph: 11.7),
      CruiseTableEntry(altitude: 12000, rpm: 2300, percentPower: 61, ktas: 139, gph: 10.4),
      CruiseTableEntry(altitude: 12000, rpm: 2200, percentPower: 55, ktas: 130, gph: 9.3),
      CruiseTableEntry(altitude: 12000, rpm: 2100, percentPower: 49, ktas: 121, gph: 8.2),
    ]),
  );

  // Piper PA-28-181 Archer III POH Performance Data (180hp, Max Gross 2550 lbs)
  static final piperPA28_181 = AircraftPerformanceData(
    name: 'Piper PA-28-181 Archer III',
    icaoType: 'PA28',
    maxGrossWeight: 2550,
    usableFuel: 48,
    emptyWeight: 1642,
    takeoffGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [665, 720, 780, 845, 920],     // SL
        [735, 800, 870, 950, 1035],    // 1000
        [815, 890, 975, 1065, 1170],   // 2000
        [910, 1000, 1100, 1210, 1335], // 3000
        [1020, 1125, 1245, 1380, 1535],// 4000
        [1150, 1280, 1425, 1590, 1785],// 5000
        [1310, 1470, 1655, 1870, 2120],// 6000
        [1510, 1715, 1955, 2235, 2570],// 7000
        [1775, 2045, 2375, 2770, 3245],// 8000
      ],
    ),
    takeoffOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1150, 1245, 1350, 1465, 1590],  // SL
        [1275, 1385, 1510, 1645, 1795],  // 1000
        [1425, 1555, 1705, 1870, 2055],  // 2000
        [1600, 1760, 1940, 2145, 2380],  // 3000
        [1815, 2010, 2235, 2490, 2790],  // 4000
        [2080, 2325, 2610, 2940, 3330],  // 5000
        [2415, 2730, 3100, 3540, 4070],  // 6000
        [2855, 3270, 3770, 4375, 5115],  // 7000
        [3455, 4025, 4725, 5600, 6695],  // 8000
      ],
    ),
    landingGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [575, 580, 590, 600, 610],   // SL
        [600, 610, 620, 630, 645],   // 1000
        [630, 640, 655, 670, 685],   // 2000
        [665, 680, 695, 710, 730],   // 3000
        [705, 720, 740, 760, 780],   // 4000
        [750, 770, 790, 815, 840],   // 5000
        [800, 825, 850, 875, 905],   // 6000
        [860, 890, 920, 950, 985],   // 7000
        [930, 965, 1000, 1040, 1085],// 8000
      ],
    ),
    landingOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1290, 1310, 1330, 1355, 1380],  // SL
        [1350, 1375, 1400, 1430, 1465],  // 1000
        [1420, 1450, 1485, 1520, 1560],  // 2000
        [1500, 1540, 1580, 1625, 1675],  // 3000
        [1595, 1645, 1695, 1750, 1810],  // 4000
        [1705, 1765, 1825, 1895, 1970],  // 5000
        [1835, 1905, 1985, 2070, 2160],  // 6000
        [1990, 2080, 2175, 2280, 2395],  // 7000
        [2180, 2295, 2420, 2560, 2710],  // 8000
      ],
    ),
    cruiseTable: CruisePerformanceTable(entries: [
      // 4000 ft
      CruiseTableEntry(altitude: 4000, rpm: 2700, percentPower: 79, ktas: 127, gph: 10.5),
      CruiseTableEntry(altitude: 4000, rpm: 2500, percentPower: 70, ktas: 121, gph: 9.2),
      CruiseTableEntry(altitude: 4000, rpm: 2400, percentPower: 65, ktas: 117, gph: 8.5),
      CruiseTableEntry(altitude: 4000, rpm: 2300, percentPower: 60, ktas: 112, gph: 7.8),
      CruiseTableEntry(altitude: 4000, rpm: 2200, percentPower: 55, ktas: 106, gph: 7.1),
      // 6000 ft
      CruiseTableEntry(altitude: 6000, rpm: 2700, percentPower: 76, ktas: 127, gph: 10.0),
      CruiseTableEntry(altitude: 6000, rpm: 2500, percentPower: 67, ktas: 120, gph: 8.8),
      CruiseTableEntry(altitude: 6000, rpm: 2400, percentPower: 62, ktas: 116, gph: 8.1),
      CruiseTableEntry(altitude: 6000, rpm: 2300, percentPower: 57, ktas: 110, gph: 7.4),
      CruiseTableEntry(altitude: 6000, rpm: 2200, percentPower: 52, ktas: 104, gph: 6.8),
      // 8000 ft
      CruiseTableEntry(altitude: 8000, rpm: 2700, percentPower: 72, ktas: 126, gph: 9.5),
      CruiseTableEntry(altitude: 8000, rpm: 2500, percentPower: 64, ktas: 119, gph: 8.3),
      CruiseTableEntry(altitude: 8000, rpm: 2400, percentPower: 59, ktas: 114, gph: 7.6),
      CruiseTableEntry(altitude: 8000, rpm: 2300, percentPower: 54, ktas: 108, gph: 7.0),
      CruiseTableEntry(altitude: 8000, rpm: 2200, percentPower: 49, ktas: 102, gph: 6.4),
      // 10000 ft
      CruiseTableEntry(altitude: 10000, rpm: 2700, percentPower: 69, ktas: 125, gph: 9.0),
      CruiseTableEntry(altitude: 10000, rpm: 2500, percentPower: 61, ktas: 117, gph: 7.8),
      CruiseTableEntry(altitude: 10000, rpm: 2400, percentPower: 56, ktas: 111, gph: 7.2),
      CruiseTableEntry(altitude: 10000, rpm: 2300, percentPower: 51, ktas: 105, gph: 6.6),
    ]),
  );

  // Piper PA-28-161 Warrior III POH Performance Data (160hp, Max Gross 2440 lbs)
  static final piperPA28_161 = AircraftPerformanceData(
    name: 'Piper PA-28-161 Warrior III',
    icaoType: 'P28A',
    maxGrossWeight: 2440,
    usableFuel: 48,
    emptyWeight: 1531,
    takeoffGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [745, 810, 880, 960, 1045],     // SL
        [825, 900, 985, 1075, 1180],    // 1000
        [920, 1010, 1105, 1215, 1340],  // 2000
        [1030, 1135, 1255, 1390, 1545], // 3000
        [1165, 1295, 1440, 1610, 1810], // 4000
        [1335, 1495, 1680, 1900, 2160], // 5000
        [1555, 1760, 2005, 2300, 2660], // 6000
        [1850, 2125, 2460, 2875, 3390], // 7000
        [2265, 2660, 3145, 3765, 4560], // 8000
      ],
    ),
    takeoffOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1295, 1405, 1530, 1665, 1815],  // SL
        [1440, 1570, 1720, 1885, 2065],  // 1000
        [1615, 1775, 1955, 2160, 2390],  // 2000
        [1825, 2020, 2245, 2505, 2800],  // 3000
        [2085, 2330, 2615, 2945, 3330],  // 4000
        [2420, 2735, 3105, 3540, 4060],  // 5000
        [2865, 3280, 3780, 4385, 5120],  // 6000
        [3490, 4065, 4780, 5665, 6785],  // 7000
        [4415, 5260, 6355, 7785, 9680],  // 8000
      ],
    ),
    landingGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [550, 555, 565, 575, 585],   // SL
        [575, 585, 595, 605, 620],   // 1000
        [605, 615, 630, 645, 660],   // 2000
        [640, 655, 670, 690, 710],   // 3000
        [680, 700, 720, 740, 765],   // 4000
        [730, 755, 780, 805, 835],   // 5000
        [790, 820, 850, 885, 920],   // 6000
        [865, 900, 940, 980, 1025],  // 7000
        [955, 1000, 1050, 1105, 1165],// 8000
      ],
    ),
    landingOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1250, 1270, 1290, 1315, 1340],  // SL
        [1310, 1335, 1360, 1390, 1425],  // 1000
        [1380, 1410, 1445, 1485, 1525],  // 2000
        [1460, 1500, 1545, 1595, 1650],  // 3000
        [1560, 1610, 1665, 1730, 1800],  // 4000
        [1680, 1745, 1820, 1900, 1990],  // 5000
        [1830, 1915, 2010, 2115, 2230],  // 6000
        [2020, 2130, 2255, 2395, 2555],  // 7000
        [2270, 2420, 2590, 2790, 3015],  // 8000
      ],
    ),
    cruiseTable: CruisePerformanceTable(entries: [
      // 4000 ft
      CruiseTableEntry(altitude: 4000, rpm: 2700, percentPower: 77, ktas: 117, gph: 9.4),
      CruiseTableEntry(altitude: 4000, rpm: 2500, percentPower: 68, ktas: 111, gph: 8.2),
      CruiseTableEntry(altitude: 4000, rpm: 2400, percentPower: 63, ktas: 107, gph: 7.5),
      CruiseTableEntry(altitude: 4000, rpm: 2300, percentPower: 58, ktas: 102, gph: 6.8),
      CruiseTableEntry(altitude: 4000, rpm: 2200, percentPower: 53, ktas: 96, gph: 6.2),
      // 6000 ft
      CruiseTableEntry(altitude: 6000, rpm: 2700, percentPower: 74, ktas: 117, gph: 8.9),
      CruiseTableEntry(altitude: 6000, rpm: 2500, percentPower: 65, ktas: 110, gph: 7.8),
      CruiseTableEntry(altitude: 6000, rpm: 2400, percentPower: 60, ktas: 105, gph: 7.1),
      CruiseTableEntry(altitude: 6000, rpm: 2300, percentPower: 55, ktas: 100, gph: 6.5),
      CruiseTableEntry(altitude: 6000, rpm: 2200, percentPower: 50, ktas: 94, gph: 5.9),
      // 8000 ft
      CruiseTableEntry(altitude: 8000, rpm: 2700, percentPower: 70, ktas: 116, gph: 8.4),
      CruiseTableEntry(altitude: 8000, rpm: 2500, percentPower: 62, ktas: 109, gph: 7.3),
      CruiseTableEntry(altitude: 8000, rpm: 2400, percentPower: 57, ktas: 104, gph: 6.7),
      CruiseTableEntry(altitude: 8000, rpm: 2300, percentPower: 52, ktas: 98, gph: 6.1),
      CruiseTableEntry(altitude: 8000, rpm: 2200, percentPower: 47, ktas: 92, gph: 5.5),
      // 10000 ft
      CruiseTableEntry(altitude: 10000, rpm: 2700, percentPower: 67, ktas: 115, gph: 7.9),
      CruiseTableEntry(altitude: 10000, rpm: 2500, percentPower: 59, ktas: 107, gph: 6.9),
      CruiseTableEntry(altitude: 10000, rpm: 2400, percentPower: 54, ktas: 102, gph: 6.3),
      CruiseTableEntry(altitude: 10000, rpm: 2300, percentPower: 49, ktas: 95, gph: 5.7),
    ]),
  );

  // Beechcraft A36 Bonanza POH Performance Data (300hp, Max Gross 3650 lbs)
  static final beechA36 = AircraftPerformanceData(
    name: 'Beechcraft A36 Bonanza',
    icaoType: 'BE36',
    maxGrossWeight: 3650,
    usableFuel: 74,
    emptyWeight: 2295,
    takeoffGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [740, 800, 865, 940, 1020],     // SL
        [815, 885, 960, 1045, 1140],    // 1000
        [905, 985, 1075, 1175, 1285],   // 2000
        [1005, 1100, 1205, 1325, 1455], // 3000
        [1125, 1240, 1365, 1510, 1670], // 4000
        [1265, 1405, 1560, 1740, 1945], // 5000
        [1440, 1615, 1815, 2045, 2315], // 6000
        [1665, 1890, 2155, 2465, 2830], // 7000
        [1970, 2270, 2630, 3065, 3590], // 8000
      ],
    ),
    takeoffOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1240, 1340, 1450, 1575, 1710],  // SL
        [1375, 1495, 1625, 1770, 1930],  // 1000
        [1535, 1675, 1835, 2010, 2210],  // 2000
        [1720, 1890, 2085, 2305, 2555],  // 3000
        [1945, 2155, 2395, 2670, 2985],  // 4000
        [2220, 2485, 2790, 3145, 3555],  // 5000
        [2575, 2915, 3315, 3785, 4340],  // 6000
        [3045, 3495, 4035, 4685, 5475],  // 7000
        [3695, 4320, 5085, 6030, 7210],  // 8000
      ],
    ),
    landingGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [660, 670, 680, 695, 710],   // SL
        [695, 710, 725, 740, 760],   // 1000
        [735, 755, 775, 795, 820],   // 2000
        [785, 805, 830, 860, 890],   // 3000
        [840, 870, 900, 935, 970],   // 4000
        [905, 945, 985, 1025, 1070], // 5000
        [985, 1035, 1085, 1140, 1200],// 6000
        [1085, 1145, 1210, 1285, 1365],// 7000
        [1210, 1290, 1380, 1480, 1590],// 8000
      ],
    ),
    landingOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1290, 1310, 1335, 1360, 1390],  // SL
        [1360, 1385, 1415, 1450, 1485],  // 1000
        [1445, 1480, 1520, 1560, 1605],  // 2000
        [1545, 1590, 1640, 1695, 1755],  // 3000
        [1670, 1730, 1795, 1865, 1945],  // 4000
        [1820, 1900, 1990, 2085, 2190],  // 5000
        [2015, 2125, 2245, 2375, 2520],  // 6000
        [2270, 2420, 2590, 2775, 2985],  // 7000
        [2615, 2825, 3065, 3335, 3645],  // 8000
      ],
    ),
    cruiseTable: CruisePerformanceTable(entries: [
      // 6000 ft
      CruiseTableEntry(altitude: 6000, rpm: 2500, percentPower: 75, ktas: 168, gph: 15.6),
      CruiseTableEntry(altitude: 6000, rpm: 2400, percentPower: 69, ktas: 161, gph: 14.0),
      CruiseTableEntry(altitude: 6000, rpm: 2300, percentPower: 63, ktas: 154, gph: 12.5),
      CruiseTableEntry(altitude: 6000, rpm: 2200, percentPower: 57, ktas: 145, gph: 11.2),
      CruiseTableEntry(altitude: 6000, rpm: 2100, percentPower: 51, ktas: 135, gph: 10.0),
      // 8000 ft
      CruiseTableEntry(altitude: 8000, rpm: 2500, percentPower: 71, ktas: 167, gph: 14.9),
      CruiseTableEntry(altitude: 8000, rpm: 2400, percentPower: 65, ktas: 160, gph: 13.3),
      CruiseTableEntry(altitude: 8000, rpm: 2300, percentPower: 59, ktas: 152, gph: 11.8),
      CruiseTableEntry(altitude: 8000, rpm: 2200, percentPower: 54, ktas: 143, gph: 10.6),
      CruiseTableEntry(altitude: 8000, rpm: 2100, percentPower: 48, ktas: 132, gph: 9.4),
      // 10000 ft
      CruiseTableEntry(altitude: 10000, rpm: 2500, percentPower: 67, ktas: 165, gph: 14.1),
      CruiseTableEntry(altitude: 10000, rpm: 2400, percentPower: 62, ktas: 158, gph: 12.6),
      CruiseTableEntry(altitude: 10000, rpm: 2300, percentPower: 56, ktas: 149, gph: 11.2),
      CruiseTableEntry(altitude: 10000, rpm: 2200, percentPower: 50, ktas: 139, gph: 9.9),
      CruiseTableEntry(altitude: 10000, rpm: 2100, percentPower: 45, ktas: 128, gph: 8.7),
      // 12000 ft
      CruiseTableEntry(altitude: 12000, rpm: 2500, percentPower: 63, ktas: 163, gph: 13.3),
      CruiseTableEntry(altitude: 12000, rpm: 2400, percentPower: 58, ktas: 155, gph: 11.8),
      CruiseTableEntry(altitude: 12000, rpm: 2300, percentPower: 52, ktas: 146, gph: 10.4),
      CruiseTableEntry(altitude: 12000, rpm: 2200, percentPower: 47, ktas: 135, gph: 9.2),
    ]),
  );

  // Cirrus SR22 POH Performance Data (310hp, Max Gross 3400 lbs)
  static final cirrusSR22 = AircraftPerformanceData(
    name: 'Cirrus SR22',
    icaoType: 'SR22',
    maxGrossWeight: 3400,
    usableFuel: 81,
    emptyWeight: 2250,
    takeoffGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [755, 820, 890, 965, 1050],     // SL
        [835, 910, 990, 1080, 1180],    // 1000
        [925, 1015, 1110, 1215, 1335],  // 2000
        [1035, 1140, 1255, 1385, 1530], // 3000
        [1165, 1290, 1430, 1595, 1780], // 4000
        [1320, 1475, 1655, 1865, 2110], // 5000
        [1515, 1715, 1950, 2230, 2560], // 6000
        [1770, 2035, 2355, 2740, 3205], // 7000
        [2115, 2480, 2930, 3490, 4190], // 8000
      ],
    ),
    takeoffOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1185, 1285, 1395, 1515, 1650],  // SL
        [1320, 1435, 1565, 1710, 1870],  // 1000
        [1475, 1615, 1775, 1950, 2150],  // 2000
        [1665, 1835, 2030, 2255, 2510],  // 3000
        [1895, 2105, 2350, 2635, 2965],  // 4000
        [2185, 2455, 2775, 3150, 3595],  // 5000
        [2560, 2915, 3345, 3860, 4490],  // 6000
        [3070, 3555, 4150, 4890, 5815],  // 7000
        [3790, 4490, 5365, 6490, 7940],  // 8000
      ],
    ),
    landingGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1025, 1040, 1055, 1075, 1095],  // SL
        [1075, 1095, 1115, 1140, 1165],  // 1000
        [1135, 1160, 1185, 1215, 1250],  // 2000
        [1205, 1235, 1270, 1310, 1355],  // 3000
        [1290, 1330, 1375, 1425, 1480],  // 4000
        [1400, 1455, 1510, 1575, 1650],  // 5000
        [1535, 1610, 1690, 1780, 1880],  // 6000
        [1710, 1810, 1920, 2045, 2185],  // 7000
        [1935, 2075, 2230, 2410, 2615],  // 8000
      ],
    ),
    landingOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [2450, 2490, 2530, 2580, 2635],  // SL
        [2575, 2625, 2680, 2745, 2815],  // 1000
        [2720, 2785, 2855, 2935, 3025],  // 2000
        [2890, 2975, 3070, 3175, 3295],  // 3000
        [3095, 3210, 3335, 3475, 3635],  // 4000
        [3360, 3510, 3680, 3870, 4085],  // 5000
        [3700, 3905, 4140, 4405, 4705],  // 6000
        [4155, 4440, 4765, 5140, 5570],  // 7000
        [4780, 5185, 5665, 6220, 6870],  // 8000
      ],
    ),
    cruiseTable: CruisePerformanceTable(entries: [
      // 6000 ft
      CruiseTableEntry(altitude: 6000, rpm: 2700, percentPower: 87, ktas: 181, gph: 18.0),
      CruiseTableEntry(altitude: 6000, rpm: 2600, percentPower: 78, ktas: 175, gph: 15.5),
      CruiseTableEntry(altitude: 6000, rpm: 2500, percentPower: 70, ktas: 167, gph: 13.5),
      CruiseTableEntry(altitude: 6000, rpm: 2400, percentPower: 63, ktas: 158, gph: 11.8),
      CruiseTableEntry(altitude: 6000, rpm: 2300, percentPower: 56, ktas: 148, gph: 10.3),
      // 8000 ft
      CruiseTableEntry(altitude: 8000, rpm: 2700, percentPower: 82, ktas: 181, gph: 17.0),
      CruiseTableEntry(altitude: 8000, rpm: 2600, percentPower: 74, ktas: 174, gph: 14.7),
      CruiseTableEntry(altitude: 8000, rpm: 2500, percentPower: 66, ktas: 166, gph: 12.8),
      CruiseTableEntry(altitude: 8000, rpm: 2400, percentPower: 59, ktas: 156, gph: 11.1),
      CruiseTableEntry(altitude: 8000, rpm: 2300, percentPower: 53, ktas: 146, gph: 9.7),
      // 10000 ft
      CruiseTableEntry(altitude: 10000, rpm: 2700, percentPower: 77, ktas: 180, gph: 16.0),
      CruiseTableEntry(altitude: 10000, rpm: 2600, percentPower: 70, ktas: 172, gph: 13.8),
      CruiseTableEntry(altitude: 10000, rpm: 2500, percentPower: 63, ktas: 163, gph: 12.0),
      CruiseTableEntry(altitude: 10000, rpm: 2400, percentPower: 56, ktas: 153, gph: 10.4),
      CruiseTableEntry(altitude: 10000, rpm: 2300, percentPower: 50, ktas: 142, gph: 9.0),
      // 12000 ft
      CruiseTableEntry(altitude: 12000, rpm: 2700, percentPower: 73, ktas: 178, gph: 15.1),
      CruiseTableEntry(altitude: 12000, rpm: 2600, percentPower: 66, ktas: 170, gph: 13.0),
      CruiseTableEntry(altitude: 12000, rpm: 2500, percentPower: 59, ktas: 160, gph: 11.2),
      CruiseTableEntry(altitude: 12000, rpm: 2400, percentPower: 53, ktas: 149, gph: 9.7),
    ]),
  );

  // Diamond DA40 POH Performance Data (180hp, Max Gross 2535 lbs)
  static final diamondDA40 = AircraftPerformanceData(
    name: 'Diamond DA40 Diamond Star',
    icaoType: 'DA40',
    maxGrossWeight: 2535,
    usableFuel: 40,
    emptyWeight: 1755,
    takeoffGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [720, 780, 845, 920, 1000],     // SL
        [795, 865, 945, 1030, 1125],    // 1000
        [885, 970, 1060, 1165, 1280],   // 2000
        [990, 1090, 1200, 1325, 1465],  // 3000
        [1115, 1235, 1370, 1525, 1700], // 4000
        [1270, 1420, 1590, 1790, 2020], // 5000
        [1465, 1660, 1890, 2160, 2480], // 6000
        [1720, 1985, 2305, 2685, 3145], // 7000
        [2070, 2440, 2895, 3455, 4155], // 8000
      ],
    ),
    takeoffOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1340, 1450, 1575, 1710, 1860],  // SL
        [1490, 1620, 1770, 1935, 2120],  // 1000
        [1670, 1830, 2015, 2220, 2455],  // 2000
        [1890, 2090, 2320, 2585, 2890],  // 3000
        [2165, 2420, 2715, 3060, 3465],  // 4000
        [2520, 2850, 3240, 3700, 4250],  // 5000
        [2985, 3430, 3960, 4600, 5385],  // 6000
        [3635, 4260, 5020, 5965, 7160],  // 7000
        [4585, 5520, 6700, 8215, 10200], // 8000
      ],
    ),
    landingGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [920, 935, 950, 970, 990],    // SL
        [965, 985, 1005, 1030, 1055], // 1000
        [1020, 1045, 1075, 1105, 1140],// 2000
        [1090, 1125, 1160, 1200, 1245],// 3000
        [1175, 1220, 1270, 1325, 1385],// 4000
        [1285, 1350, 1420, 1495, 1580],// 5000
        [1430, 1520, 1620, 1730, 1855],// 6000
        [1625, 1760, 1910, 2085, 2285],// 7000
        [1905, 2105, 2345, 2630, 2975],// 8000
      ],
    ),
    landingOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1835, 1865, 1900, 1940, 1980],  // SL
        [1925, 1965, 2010, 2060, 2115],  // 1000
        [2030, 2085, 2145, 2210, 2285],  // 2000
        [2165, 2235, 2315, 2405, 2505],  // 3000
        [2330, 2430, 2540, 2665, 2810],  // 4000
        [2550, 2690, 2850, 3030, 3240],  // 5000
        [2850, 3055, 3290, 3565, 3885],  // 6000
        [3280, 3590, 3960, 4400, 4935],  // 7000
        [3920, 4420, 5025, 5775, 6720],  // 8000
      ],
    ),
    cruiseTable: CruisePerformanceTable(entries: [
      // 4000 ft
      CruiseTableEntry(altitude: 4000, rpm: 2500, percentPower: 78, ktas: 138, gph: 10.8),
      CruiseTableEntry(altitude: 4000, rpm: 2400, percentPower: 72, ktas: 133, gph: 9.8),
      CruiseTableEntry(altitude: 4000, rpm: 2300, percentPower: 66, ktas: 127, gph: 8.8),
      CruiseTableEntry(altitude: 4000, rpm: 2200, percentPower: 60, ktas: 121, gph: 7.9),
      CruiseTableEntry(altitude: 4000, rpm: 2100, percentPower: 54, ktas: 114, gph: 7.1),
      // 6000 ft
      CruiseTableEntry(altitude: 6000, rpm: 2500, percentPower: 74, ktas: 138, gph: 10.2),
      CruiseTableEntry(altitude: 6000, rpm: 2400, percentPower: 68, ktas: 132, gph: 9.2),
      CruiseTableEntry(altitude: 6000, rpm: 2300, percentPower: 62, ktas: 126, gph: 8.3),
      CruiseTableEntry(altitude: 6000, rpm: 2200, percentPower: 57, ktas: 119, gph: 7.5),
      CruiseTableEntry(altitude: 6000, rpm: 2100, percentPower: 51, ktas: 112, gph: 6.7),
      // 8000 ft
      CruiseTableEntry(altitude: 8000, rpm: 2500, percentPower: 70, ktas: 137, gph: 9.6),
      CruiseTableEntry(altitude: 8000, rpm: 2400, percentPower: 65, ktas: 131, gph: 8.7),
      CruiseTableEntry(altitude: 8000, rpm: 2300, percentPower: 59, ktas: 124, gph: 7.8),
      CruiseTableEntry(altitude: 8000, rpm: 2200, percentPower: 54, ktas: 117, gph: 7.0),
      CruiseTableEntry(altitude: 8000, rpm: 2100, percentPower: 48, ktas: 109, gph: 6.3),
      // 10000 ft
      CruiseTableEntry(altitude: 10000, rpm: 2500, percentPower: 66, ktas: 136, gph: 9.0),
      CruiseTableEntry(altitude: 10000, rpm: 2400, percentPower: 61, ktas: 129, gph: 8.1),
      CruiseTableEntry(altitude: 10000, rpm: 2300, percentPower: 55, ktas: 122, gph: 7.3),
      CruiseTableEntry(altitude: 10000, rpm: 2200, percentPower: 50, ktas: 114, gph: 6.5),
    ]),
  );

  // Cessna 152 POH Performance Data (1979 Model, Max Gross Weight)
  static final cessna152 = AircraftPerformanceData(
    name: 'Cessna 152',
    icaoType: 'C152',
    maxGrossWeight: 1670,
    usableFuel: 24.5,
    emptyWeight: 1109,
    takeoffGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [635, 685, 735, 795, 855],    // SL
        [695, 750, 810, 875, 945],    // 1000
        [765, 825, 895, 970, 1050],   // 2000
        [845, 915, 995, 1080, 1175],  // 3000
        [935, 1015, 1100, 1200, 1310],// 4000
        [1040, 1130, 1235, 1350, 1480],// 5000
        [1165, 1275, 1400, 1540, 1700],// 6000
        [1320, 1455, 1610, 1790, 2000],// 7000
        [1520, 1695, 1900, 2140, 2430],// 8000
      ],
    ),
    takeoffOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1140, 1225, 1320, 1420, 1530],  // SL
        [1260, 1360, 1465, 1580, 1705],  // 1000
        [1400, 1515, 1640, 1775, 1925],  // 2000
        [1565, 1700, 1850, 2015, 2200],  // 3000
        [1760, 1910, 2080, 2280, 2505],  // 4000
        [1990, 2175, 2390, 2640, 2920],  // 5000
        [2280, 2510, 2785, 3110, 3490],  // 6000
        [2660, 2960, 3330, 3770, 4300],  // 7000
        [3165, 3590, 4110, 4750, 5550],  // 8000
      ],
    ),
    landingGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [445, 450, 455, 460, 465],   // SL
        [460, 465, 470, 480, 485],   // 1000
        [475, 485, 490, 500, 505],   // 2000
        [495, 505, 510, 520, 530],   // 3000
        [515, 525, 535, 545, 555],   // 4000
        [540, 550, 560, 570, 580],   // 5000
        [565, 575, 590, 600, 615],   // 6000
        [595, 610, 620, 635, 650],   // 7000
        [630, 645, 660, 675, 695],   // 8000
      ],
    ),
    landingOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1075, 1090, 1100, 1115, 1130],  // SL
        [1115, 1130, 1145, 1160, 1180],  // 1000
        [1160, 1175, 1195, 1215, 1235],  // 2000
        [1210, 1230, 1250, 1275, 1300],  // 3000
        [1265, 1290, 1315, 1340, 1370],  // 4000
        [1330, 1355, 1385, 1415, 1450],  // 5000
        [1400, 1430, 1465, 1500, 1540],  // 6000
        [1480, 1520, 1555, 1600, 1645],  // 7000
        [1575, 1620, 1665, 1715, 1770],  // 8000
      ],
    ),
    cruiseTable: CruisePerformanceTable(entries: [
      // 4000 ft
      CruiseTableEntry(altitude: 4000, rpm: 2550, percentPower: 75, ktas: 107, gph: 6.1),
      CruiseTableEntry(altitude: 4000, rpm: 2400, percentPower: 65, ktas: 101, gph: 5.4),
      CruiseTableEntry(altitude: 4000, rpm: 2300, percentPower: 58, ktas: 96, gph: 4.9),
      CruiseTableEntry(altitude: 4000, rpm: 2200, percentPower: 52, ktas: 91, gph: 4.5),
      // 6000 ft
      CruiseTableEntry(altitude: 6000, rpm: 2550, percentPower: 71, ktas: 106, gph: 5.8),
      CruiseTableEntry(altitude: 6000, rpm: 2400, percentPower: 62, ktas: 100, gph: 5.1),
      CruiseTableEntry(altitude: 6000, rpm: 2300, percentPower: 55, ktas: 95, gph: 4.7),
      CruiseTableEntry(altitude: 6000, rpm: 2200, percentPower: 49, ktas: 89, gph: 4.3),
      // 8000 ft
      CruiseTableEntry(altitude: 8000, rpm: 2550, percentPower: 67, ktas: 105, gph: 5.5),
      CruiseTableEntry(altitude: 8000, rpm: 2400, percentPower: 59, ktas: 99, gph: 4.9),
      CruiseTableEntry(altitude: 8000, rpm: 2300, percentPower: 52, ktas: 93, gph: 4.4),
      CruiseTableEntry(altitude: 8000, rpm: 2200, percentPower: 46, ktas: 87, gph: 4.0),
      // 10000 ft
      CruiseTableEntry(altitude: 10000, rpm: 2550, percentPower: 63, ktas: 103, gph: 5.2),
      CruiseTableEntry(altitude: 10000, rpm: 2400, percentPower: 55, ktas: 97, gph: 4.6),
      CruiseTableEntry(altitude: 10000, rpm: 2300, percentPower: 49, ktas: 91, gph: 4.2),
      CruiseTableEntry(altitude: 10000, rpm: 2200, percentPower: 43, ktas: 84, gph: 3.7),
    ]),
  );

  // Piper PA-44 Seminole POH Performance Data (Twin 180hp, Max Gross 3800 lbs)
  static final piperPA44 = AircraftPerformanceData(
    name: 'Piper PA-44 Seminole',
    icaoType: 'PA44',
    maxGrossWeight: 3800,
    usableFuel: 108,
    emptyWeight: 2354,
    takeoffGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [715, 775, 840, 910, 990],      // SL
        [790, 860, 935, 1020, 1110],    // 1000
        [880, 960, 1050, 1150, 1260],   // 2000
        [985, 1080, 1190, 1310, 1450],  // 3000
        [1110, 1225, 1360, 1510, 1690], // 4000
        [1265, 1405, 1575, 1770, 2000], // 5000
        [1460, 1645, 1865, 2125, 2435], // 6000
        [1720, 1965, 2265, 2630, 3080], // 7000
        [2085, 2430, 2860, 3400, 4090], // 8000
      ],
    ),
    takeoffOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1165, 1260, 1365, 1480, 1605],  // SL
        [1295, 1405, 1530, 1665, 1815],  // 1000
        [1450, 1580, 1730, 1895, 2080],  // 2000
        [1635, 1795, 1975, 2180, 2410],  // 3000
        [1860, 2055, 2280, 2540, 2835],  // 4000
        [2140, 2385, 2675, 3010, 3400],  // 5000
        [2500, 2820, 3200, 3650, 4185],  // 6000
        [2985, 3410, 3930, 4560, 5330],  // 7000
        [3670, 4270, 5020, 5960, 7150],  // 8000
      ],
    ),
    landingGroundRoll: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [590, 595, 605, 610, 620],   // SL
        [610, 620, 630, 640, 650],   // 1000
        [640, 650, 660, 670, 685],   // 2000
        [670, 680, 695, 710, 725],   // 3000
        [705, 720, 735, 750, 770],   // 4000
        [745, 760, 780, 800, 820],   // 5000
        [790, 810, 830, 855, 880],   // 6000
        [845, 870, 895, 920, 950],   // 7000
        [905, 935, 965, 1000, 1040], // 8000
      ],
    ),
    landingOver50ft: PerformanceTable(
      pressureAltitudes: [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000],
      temperatures: [0, 10, 20, 30, 40],
      values: [
        [1315, 1335, 1355, 1375, 1400],  // SL
        [1370, 1395, 1420, 1445, 1475],  // 1000
        [1435, 1465, 1495, 1530, 1565],  // 2000
        [1510, 1545, 1585, 1625, 1670],  // 3000
        [1600, 1640, 1690, 1740, 1795],  // 4000
        [1705, 1755, 1810, 1870, 1935],  // 5000
        [1830, 1890, 1955, 2025, 2105],  // 6000
        [1985, 2055, 2135, 2220, 2315],  // 7000
        [2175, 2265, 2360, 2470, 2590],  // 8000
      ],
    ),
    cruiseTable: CruisePerformanceTable(entries: [
      // 4000 ft (Both engines, GPH is total for both)
      CruiseTableEntry(altitude: 4000, rpm: 2400, percentPower: 75, ktas: 161, gph: 16.4),
      CruiseTableEntry(altitude: 4000, rpm: 2300, percentPower: 65, ktas: 153, gph: 14.2),
      CruiseTableEntry(altitude: 4000, rpm: 2200, percentPower: 55, ktas: 143, gph: 12.0),
      // 6000 ft
      CruiseTableEntry(altitude: 6000, rpm: 2400, percentPower: 72, ktas: 163, gph: 15.8),
      CruiseTableEntry(altitude: 6000, rpm: 2300, percentPower: 62, ktas: 154, gph: 13.6),
      CruiseTableEntry(altitude: 6000, rpm: 2200, percentPower: 52, ktas: 144, gph: 11.4),
      // 8000 ft
      CruiseTableEntry(altitude: 8000, rpm: 2400, percentPower: 68, ktas: 164, gph: 15.0),
      CruiseTableEntry(altitude: 8000, rpm: 2300, percentPower: 59, ktas: 155, gph: 13.0),
      CruiseTableEntry(altitude: 8000, rpm: 2200, percentPower: 50, ktas: 145, gph: 10.8),
      // 10000 ft
      CruiseTableEntry(altitude: 10000, rpm: 2400, percentPower: 65, ktas: 165, gph: 14.2),
      CruiseTableEntry(altitude: 10000, rpm: 2300, percentPower: 56, ktas: 156, gph: 12.4),
      CruiseTableEntry(altitude: 10000, rpm: 2200, percentPower: 47, ktas: 145, gph: 10.2),
      // 12000 ft
      CruiseTableEntry(altitude: 12000, rpm: 2400, percentPower: 61, ktas: 165, gph: 13.4),
      CruiseTableEntry(altitude: 12000, rpm: 2300, percentPower: 53, ktas: 156, gph: 11.6),
      CruiseTableEntry(altitude: 12000, rpm: 2200, percentPower: 44, ktas: 144, gph: 9.6),
    ]),
  );

  static List<AircraftPerformanceData> get all => [
    cessna152,
    cessna172sp,
    cessna182t,
    piperPA28_181,
    piperPA28_161,
    piperPA44,
    beechA36,
    cirrusSR22,
    diamondDA40,
  ];

  static AircraftPerformanceData? getByIcao(String icao) {
    try {
      return all.firstWhere((a) => a.icaoType.toLowerCase() == icao.toLowerCase());
    } catch (e) {
      return null;
    }
  }
}

class WnbStationDef {
  final String name;
  final double arm;
  final double defaultWeight;
  
  const WnbStationDef({required this.name, required this.arm, this.defaultWeight = 0});
  
  Map<String, dynamic> toMap() => {'name': name, 'arm': arm, 'defaultWeight': defaultWeight};
  
  factory WnbStationDef.fromMap(Map<String, dynamic> map) {
    return WnbStationDef(
      name: (map['name'] ?? '') as String,
      arm: (map['arm'] ?? 0).toDouble(),
      defaultWeight: (map['defaultWeight'] ?? 0).toDouble(),
    );
  }
}

class WnbData {
  final List<WnbStationDef> stations;
  final List<Offset> envelopePoints;
  final double minArm;
  final double maxArm;
  final double minWeight;
  final double maxWeight;
  
  const WnbData({
    required this.stations,
    required this.envelopePoints,
    required this.minArm,
    required this.maxArm,
    required this.minWeight,
    required this.maxWeight,
  });
  
  factory WnbData.defaultData() {
    return WnbData(
      stations: [
        WnbStationDef(name: 'Empty Weight', arm: 40, defaultWeight: 1500),
        WnbStationDef(name: 'Pilot & Copilot', arm: 37, defaultWeight: 340),
        WnbStationDef(name: 'Rear Passengers', arm: 73, defaultWeight: 0),
        WnbStationDef(name: 'Baggage', arm: 95, defaultWeight: 0),
        WnbStationDef(name: 'Fuel (lbs)', arm: 48, defaultWeight: 288),
      ],
      envelopePoints: [
        const Offset(35, 1500),
        const Offset(47.3, 1500),
        const Offset(47.3, 2400),
        const Offset(41, 2400),
        const Offset(35, 1950),
      ],
      minArm: 33,
      maxArm: 50,
      minWeight: 1400,
      maxWeight: 2600,
    );
  }
  
  String toJson() {
    return jsonEncode({
      'stations': stations.map((s) => s.toMap()).toList(),
      'envelopePoints': envelopePoints.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'minArm': minArm,
      'maxArm': maxArm,
      'minWeight': minWeight,
      'maxWeight': maxWeight,
    });
  }

  factory WnbData.fromJson(String json) {
    final String trimmed = json.trim();
    if (trimmed.isEmpty) {
      return WnbData.defaultData();
    }
    try {
      final dynamic decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return WnbData._fromDecodedMap(decoded);
      }
      if (decoded is Map) {
        return WnbData._fromDecodedMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // try legacy format below
    }
    return WnbData._fromJsonLegacyRegex(trimmed);
  }

  static WnbData _fromDecodedMap(Map<String, dynamic> m) {
    List<WnbStationDef> stations = [];
    final stationsRaw = m['stations'];
    if (stationsRaw is List) {
      for (final e in stationsRaw) {
        if (e is Map<String, dynamic>) {
          stations.add(WnbStationDef.fromMap(e));
        } else if (e is Map) {
          stations.add(WnbStationDef.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }
    List<Offset> envelopePoints = [];
    final pts = m['envelopePoints'];
    if (pts is List) {
      for (final e in pts) {
        if (e is Map) {
          final em = Map<String, dynamic>.from(e);
          final Object? x = em['x'];
          final Object? y = em['y'];
          if (x != null && y != null) {
            envelopePoints.add(Offset(
              (x as num).toDouble(),
              (y as num).toDouble(),
            ));
          }
        }
      }
    }
    return WnbData(
      stations: stations,
      envelopePoints: envelopePoints,
      minArm: (m['minArm'] as num?)?.toDouble() ?? 35,
      maxArm: (m['maxArm'] as num?)?.toDouble() ?? 50,
      minWeight: (m['minWeight'] as num?)?.toDouble() ?? 1000,
      maxWeight: (m['maxWeight'] as num?)?.toDouble() ?? 2800,
    );
  }

  /// Older app versions wrote a non-standard JSON-like string; keep best-effort parse for migration.
  static WnbData _fromJsonLegacyRegex(String json) {
    try {
      json = json.replaceAll(RegExp(r'\s'), '');

      List<WnbStationDef> stations = [];
      RegExp stationsRegex = RegExp(r'"stations":\[(.*?)\]');
      Match? stationsMatch = stationsRegex.firstMatch(json);
      if (stationsMatch != null) {
        String stationsStr = stationsMatch.group(1) ?? '';
        RegExp stationRegex = RegExp(r'\{"name":"([^"]+)","arm":([\d.-]+),"defaultWeight":([\d.-]+)\}');
        for (Match m in stationRegex.allMatches(stationsStr)) {
          stations.add(WnbStationDef(
            name: m.group(1) ?? '',
            arm: double.tryParse(m.group(2) ?? '0') ?? 0,
            defaultWeight: double.tryParse(m.group(3) ?? '0') ?? 0,
          ));
        }
      }

      List<Offset> envelopePoints = [];
      RegExp pointsRegex = RegExp(r'"envelopePoints":\[(.*?)\]');
      Match? pointsMatch = pointsRegex.firstMatch(json);
      if (pointsMatch != null) {
        String pointsStr = pointsMatch.group(1) ?? '';
        RegExp pointRegex = RegExp(r'\{"x":([\d.-]+),"y":([\d.-]+)\}');
        for (Match m in pointRegex.allMatches(pointsStr)) {
          envelopePoints.add(Offset(
            double.tryParse(m.group(1) ?? '0') ?? 0,
            double.tryParse(m.group(2) ?? '0') ?? 0,
          ));
        }
      }

      double minArm = double.tryParse(RegExp(r'"minArm":([\d.-]+)').firstMatch(json)?.group(1) ?? '35') ?? 35;
      double maxArm = double.tryParse(RegExp(r'"maxArm":([\d.-]+)').firstMatch(json)?.group(1) ?? '50') ?? 50;
      double minWeight = double.tryParse(RegExp(r'"minWeight":([\d.-]+)').firstMatch(json)?.group(1) ?? '1000') ?? 1000;
      double maxWeight = double.tryParse(RegExp(r'"maxWeight":([\d.-]+)').firstMatch(json)?.group(1) ?? '2800') ?? 2800;

      return WnbData(
        stations: stations,
        envelopePoints: envelopePoints,
        minArm: minArm,
        maxArm: maxArm,
        minWeight: minWeight,
        maxWeight: maxWeight,
      );
    } catch (e) {
      return WnbData.defaultData();
    }
  }
}

class CommonWnbData {
  static WnbData? getWnbData(String aircraftName) {
    String name = aircraftName.toLowerCase();
    
    if (name.contains('c152') || name.contains('cessna 152')) {
      return cessna152Wnb;
    } else if (name.contains('c172') || name.contains('cessna 172')) {
      return cessna172Wnb;
    } else if (name.contains('c182') || name.contains('cessna 182')) {
      return cessna182Wnb;
    } else if (name.contains('pa-28-181') || name.contains('archer')) {
      return piperPA28_181Wnb;
    } else if (name.contains('pa-28-161') || name.contains('warrior')) {
      return piperPA28_161Wnb;
    } else if (name.contains('pa-44') || name.contains('seminole')) {
      return piperPA44Wnb;
    } else if (name.contains('a36') || name.contains('bonanza')) {
      return beechA36Wnb;
    } else if (name.contains('sr22') || name.contains('cirrus')) {
      return cirrusSR22Wnb;
    } else if (name.contains('da40') || name.contains('diamond')) {
      return diamondDA40Wnb;
    }
    
    return null;
  }
  
  // Cessna 152 W&B (from POH)
  static const cessna152Wnb = WnbData(
    stations: [
      WnbStationDef(name: 'Empty Weight', arm: 28.3, defaultWeight: 1104),
      WnbStationDef(name: 'Front Seats', arm: 39.0, defaultWeight: 340),
      WnbStationDef(name: 'Baggage Area 1', arm: 64.0, defaultWeight: 0),
      WnbStationDef(name: 'Fuel (lbs)', arm: 42.0, defaultWeight: 152), // 25.3 gal usable @ 6 lbs/gal
    ],
    envelopePoints: [
      Offset(31.0, 1100),
      Offset(36.5, 1100),
      Offset(36.5, 1670),
      Offset(33.0, 1670),
      Offset(31.0, 1350),
    ],
    minArm: 29,
    maxArm: 39,
    minWeight: 1000,
    maxWeight: 1800,
  );
  
  // Cessna 172S W&B (from POH)
  static const cessna172Wnb = WnbData(
    stations: [
      WnbStationDef(name: 'Empty Weight', arm: 40.5, defaultWeight: 1663),
      WnbStationDef(name: 'Front Seats', arm: 37.0, defaultWeight: 340),
      WnbStationDef(name: 'Rear Seats', arm: 73.0, defaultWeight: 0),
      WnbStationDef(name: 'Baggage Area 1', arm: 95.0, defaultWeight: 0),
      WnbStationDef(name: 'Baggage Area 2', arm: 123.0, defaultWeight: 0),
      WnbStationDef(name: 'Fuel (lbs)', arm: 48.0, defaultWeight: 318), // 53 gal usable @ 6 lbs/gal
    ],
    envelopePoints: [
      Offset(35.0, 1500),
      Offset(47.3, 1500),
      Offset(47.3, 2550),
      Offset(41.0, 2550),
      Offset(35.0, 1950),
    ],
    minArm: 33,
    maxArm: 50,
    minWeight: 1400,
    maxWeight: 2700,
  );
  
  // Cessna 182T W&B (from POH)
  static const cessna182Wnb = WnbData(
    stations: [
      WnbStationDef(name: 'Empty Weight', arm: 41.0, defaultWeight: 1970),
      WnbStationDef(name: 'Front Seats', arm: 37.0, defaultWeight: 340),
      WnbStationDef(name: 'Rear Seats', arm: 74.0, defaultWeight: 0),
      WnbStationDef(name: 'Baggage Area 1', arm: 96.0, defaultWeight: 0),
      WnbStationDef(name: 'Baggage Area 2', arm: 123.0, defaultWeight: 0),
      WnbStationDef(name: 'Fuel (lbs)', arm: 46.0, defaultWeight: 456), // 76 gal usable @ 6 lbs/gal
    ],
    envelopePoints: [
      Offset(35.0, 1800),
      Offset(47.0, 1800),
      Offset(47.0, 3100),
      Offset(38.5, 3100),
      Offset(35.0, 2100),
    ],
    minArm: 33,
    maxArm: 50,
    minWeight: 1700,
    maxWeight: 3200,
  );
  
  // Piper PA-28-181 Archer W&B (from POH)
  static const piperPA28_181Wnb = WnbData(
    stations: [
      WnbStationDef(name: 'Empty Weight', arm: 85.0, defaultWeight: 1500),
      WnbStationDef(name: 'Front Seats', arm: 80.5, defaultWeight: 340),
      WnbStationDef(name: 'Rear Seats', arm: 118.1, defaultWeight: 0),
      WnbStationDef(name: 'Baggage', arm: 142.8, defaultWeight: 0),
      WnbStationDef(name: 'Fuel (lbs)', arm: 95.0, defaultWeight: 288), // 48 gal usable @ 6 lbs/gal
    ],
    envelopePoints: [
      Offset(80.7, 1400),
      Offset(93.0, 1400),
      Offset(93.0, 2550),
      Offset(84.0, 2550),
      Offset(80.7, 1950),
    ],
    minArm: 78,
    maxArm: 96,
    minWeight: 1300,
    maxWeight: 2700,
  );
  
  // Piper PA-28-161 Warrior W&B (from POH)
  static const piperPA28_161Wnb = WnbData(
    stations: [
      WnbStationDef(name: 'Empty Weight', arm: 83.0, defaultWeight: 1455),
      WnbStationDef(name: 'Front Seats', arm: 80.5, defaultWeight: 340),
      WnbStationDef(name: 'Rear Seats', arm: 118.1, defaultWeight: 0),
      WnbStationDef(name: 'Baggage', arm: 142.8, defaultWeight: 0),
      WnbStationDef(name: 'Fuel (lbs)', arm: 95.0, defaultWeight: 288), // 48 gal usable @ 6 lbs/gal
    ],
    envelopePoints: [
      Offset(82.0, 1400),
      Offset(93.0, 1400),
      Offset(93.0, 2325),
      Offset(84.0, 2325),
      Offset(82.0, 1700),
    ],
    minArm: 80,
    maxArm: 96,
    minWeight: 1300,
    maxWeight: 2500,
  );
  
  // Piper PA-44 Seminole W&B (from POH)
  static const piperPA44Wnb = WnbData(
    stations: [
      WnbStationDef(name: 'Empty Weight', arm: 91.0, defaultWeight: 2600),
      WnbStationDef(name: 'Front Seats', arm: 85.5, defaultWeight: 340),
      WnbStationDef(name: 'Rear Seats', arm: 118.0, defaultWeight: 0),
      WnbStationDef(name: 'Baggage (nose)', arm: 37.5, defaultWeight: 0),
      WnbStationDef(name: 'Baggage (aft)', arm: 147.0, defaultWeight: 0),
      WnbStationDef(name: 'Fuel (lbs)', arm: 93.6, defaultWeight: 432), // 72 gal usable @ 6 lbs/gal
    ],
    envelopePoints: [
      Offset(85.0, 2400),
      Offset(94.6, 2400),
      Offset(94.6, 3800),
      Offset(87.0, 3800),
      Offset(85.0, 3100),
    ],
    minArm: 83,
    maxArm: 98,
    minWeight: 2200,
    maxWeight: 4000,
  );
  
  // Beechcraft A36 Bonanza W&B (from POH)
  static const beechA36Wnb = WnbData(
    stations: [
      WnbStationDef(name: 'Empty Weight', arm: 81.0, defaultWeight: 2220),
      WnbStationDef(name: 'Front Seats', arm: 82.0, defaultWeight: 340),
      WnbStationDef(name: 'Middle Seats', arm: 117.0, defaultWeight: 0),
      WnbStationDef(name: 'Rear Seats', arm: 147.0, defaultWeight: 0),
      WnbStationDef(name: 'Baggage', arm: 174.0, defaultWeight: 0),
      WnbStationDef(name: 'Fuel (lbs)', arm: 75.0, defaultWeight: 444), // 74 gal usable @ 6 lbs/gal
    ],
    envelopePoints: [
      Offset(77.0, 2200),
      Offset(88.0, 2200),
      Offset(88.0, 3650),
      Offset(80.0, 3650),
      Offset(77.0, 2800),
    ],
    minArm: 75,
    maxArm: 92,
    minWeight: 2000,
    maxWeight: 3850,
  );
  
  // Cirrus SR22 W&B (from POH)
  static const cirrusSR22Wnb = WnbData(
    stations: [
      WnbStationDef(name: 'Empty Weight', arm: 141.0, defaultWeight: 2250),
      WnbStationDef(name: 'Front Seats', arm: 137.0, defaultWeight: 340),
      WnbStationDef(name: 'Rear Seats', arm: 175.0, defaultWeight: 0),
      WnbStationDef(name: 'Baggage', arm: 204.0, defaultWeight: 0),
      WnbStationDef(name: 'Fuel (lbs)', arm: 151.0, defaultWeight: 528), // 88 gal usable @ 6 lbs/gal
    ],
    envelopePoints: [
      Offset(137.5, 2100),
      Offset(148.0, 2100),
      Offset(148.0, 3400),
      Offset(140.0, 3400),
      Offset(137.5, 2600),
    ],
    minArm: 135,
    maxArm: 152,
    minWeight: 2000,
    maxWeight: 3600,
  );
  
  // Diamond DA40 W&B (from POH)
  static const diamondDA40Wnb = WnbData(
    stations: [
      WnbStationDef(name: 'Empty Weight', arm: 2.395, defaultWeight: 1755),
      WnbStationDef(name: 'Front Seats', arm: 2.3, defaultWeight: 340),
      WnbStationDef(name: 'Rear Seats', arm: 3.4, defaultWeight: 0),
      WnbStationDef(name: 'Baggage', arm: 4.0, defaultWeight: 0),
      WnbStationDef(name: 'Fuel (lbs)', arm: 2.52, defaultWeight: 288), // 48 gal usable @ 6 lbs/gal
    ],
    envelopePoints: [
      Offset(2.2, 1600),
      Offset(2.55, 1600),
      Offset(2.55, 2535),
      Offset(2.35, 2535),
      Offset(2.2, 2000),
    ],
    minArm: 2.1,
    maxArm: 2.7,
    minWeight: 1500,
    maxWeight: 2700,
  );
}
