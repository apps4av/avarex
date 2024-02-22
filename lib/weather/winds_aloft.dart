import 'package:avaremp/weather/weather.dart';

class WindsAloft extends Weather {
  String w3k;
  String w6k;
  String w9k;
  String w12k;
  String w18k;
  String w24k;
  String w30k;
  String w34k;
  String w39k;

  WindsAloft(super.station, super.expires, this.w3k, this.w6k, this.w9k, this.w12k, this.w18k, this.w24k, this.w30k, this.w34k, this.w39k);

  (int?, int?) decodeWind(String wind) {

    if(wind.length < 4) {
      return (null, null);
    }

    int dir;
    int speed;
    try {
      dir = int.parse(wind.substring(0, 2)) * 10;
      speed = int.parse(wind.substring(2, 4));
    }
    catch(e) {
      return (null, null);
    }

    if(dir == 990 && speed == 0) {
      return (0, 0); // light and variable
    }
    if(dir >= 510) {
      dir -= 500;
      speed += 100;
    }

    return(dir, speed);
  }

  (double?, double?) getWindAtAltitude(double altitude) {
    String wHigher;
    String wLower;
    double higherAltitude;
    double lowerAltitude;

    // slope of line, wind at y and altitude at x, y = mx + b
    // slope = (wind_at_higher_altitude - wind_at_lower_altitude) / (higher_altitude - lower_altitude)
    // wind =  slope * altitude + wind_intercept
    // wind_intercept = wind_at_lower_altitude - slope * lower_altitude

    // fill missing wind from higher altitude
    w34k = w34k.isEmpty ? w39k : w34k;
    w30k = w30k.isEmpty ? w34k : w30k;
    w24k = w24k.isEmpty ? w30k : w24k;
    w18k = w18k.isEmpty ? w24k : w18k;
    w12k = w12k.isEmpty ? w18k : w12k;
    w9k = w9k.isEmpty ? w12k : w9k;
    w6k = w6k.isEmpty ? w9k : w6k;
    w3k = w3k.isEmpty ? w6k : w3k;

    if (altitude < 0) {
      return (0, 0);
    }
    else if (altitude >= 0 && altitude < 3000) {
      higherAltitude = 3000;
      lowerAltitude = 0;
      wHigher = w3k;
      wLower = w3k;
    }
    else if (altitude >= 3000 && altitude < 6000) {
      higherAltitude = 6000;
      lowerAltitude = 3000;
      wHigher = w6k;
      wLower = w3k;
    }
    else if (altitude >= 6000 && altitude < 9000) {
      higherAltitude = 9000;
      lowerAltitude = 6000;
      wHigher = w9k;
      wLower = w6k;
    }
    else if (altitude >= 9000 && altitude < 12000) {
      higherAltitude = 12000;
      lowerAltitude = 9000;
      wHigher = w12k;
      wLower = w9k;
    }
    else if (altitude >= 12000 && altitude < 18000) {
      higherAltitude = 18000;
      lowerAltitude = 12000;
      wHigher = w18k;
      wLower = w12k;
    }
    else if (altitude >= 18000 && altitude < 24000) {
      higherAltitude = 24000;
      lowerAltitude = 18000;
      wHigher = w24k;
      wLower = w18k;
    }
    else if (altitude >= 24000 && altitude < 30000) {
      higherAltitude = 30000;
      lowerAltitude = 24000;
      wHigher = w30k;
      wLower = w24k;
    }
    else if (altitude >= 30000 && altitude < 34000) {
      higherAltitude = 34000;
      lowerAltitude = 30000;
      wHigher = w34k;
      wLower = w30k;
    }
    else {
      higherAltitude = 39000;
      lowerAltitude = 34000;
      wHigher = w39k;
      wLower = w34k;
    }

    try {
      int? higherWindDir, lowerWindDir;
      int? higherWindSpeed, lowerWindSpeed;

      (higherWindSpeed, higherWindDir) = decodeWind(wHigher);
      (lowerWindSpeed, lowerWindDir) = decodeWind(wLower);
      if(higherWindSpeed == null ||  higherWindDir == null || lowerWindSpeed == null ||  lowerWindDir == null) {
        return (null, null);
      }
      double slope = ((higherWindSpeed - lowerWindSpeed) /
          (higherAltitude - lowerAltitude));
      double intercept = lowerWindSpeed - slope * lowerAltitude;
      double speed = slope * altitude + intercept;

      slope = ((higherWindDir - lowerWindDir) / (higherAltitude - lowerAltitude));
      intercept = lowerWindDir - slope * lowerAltitude;
      double dir = slope * altitude + intercept;

      return (speed, dir);
    }
    catch (e) {}

    return (null, null);
  }

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "w3k": w3k,
      "w6k": w6k,
      "w9k": w9k,
      "w12k": w12k,
      "w18k": w18k,
      "w24k": w24k,
      "w30k": w30k,
      "w34k": w34k,
      "w39k": w39k,
    };
    return map;
  }

  factory WindsAloft.fromMap(Map<String, dynamic> maps) {

    return WindsAloft(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      maps['w3k'] as String,
      maps['w6k'] as String,
      maps['w9k'] as String,
      maps['w12k'] as String,
      maps['w18k'] as String,
      maps['w24k'] as String,
      maps['w30k'] as String,
      maps['w34k'] as String,
      maps['w39k'] as String,
    );
  }

}

