// Open-Meteo winds-aloft provider.
//
// Fills the winds-aloft gap outside the US: the built-in winds come from NWS
// FB text products that only cover the US and its territories, so anywhere else
// (Europe, etc.) the "nearest station" is thousands of miles away and useless.
// Open-Meteo exposes pressure-level wind speed/direction plus geopotential
// height globally, which we convert into the app's existing [WindsAloft] slots
// (0/3k/6k/9k/12k/18k/24k/30k/34k/39k ft) so the Wind tab renders unchanged.
//
// Data © Open-Meteo.com, CC BY 4.0. The free endpoint is used by default; a
// user may supply a personal Open-Meteo API key for commercial-compliant use,
// in which case the customer endpoint is used. No key is embedded in the app.
//
// The parsing is pure and unit-tested; only [fetch] performs I/O.

import 'dart:convert';
import 'dart:isolate';

import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OpenMeteoWinds {
  OpenMeteoWinds._();

  static const String attribution = 'Winds © Open-Meteo.com, CC BY 4.0';

  // Beyond this great-circle distance (km) from the nearest US winds-aloft
  // station, the US FB product does not apply and Open-Meteo should be used.
  static const double usStationMaxKm = 550;

  static const String freeHost = 'api.open-meteo.com';
  static const String customerHost = 'customer-api.open-meteo.com';

  // Pressure levels (hPa) requested; span the surface up to ~45,000 ft so the
  // fixed winds-aloft slots can be bracketed for interpolation.
  static const List<int> _levelsHpa = [
    1000, 925, 850, 700, 600, 500, 400, 300, 250, 200, 150,
  ];

  // Winds-aloft altitude slots in feet, in WindsAloft field order.
  static const List<int> slotFt = [
    0, 3000, 6000, 9000, 12000, 18000, 24000, 30000, 34000, 39000,
  ];

  static const double _mToFt = 3.28084;

  static const Distance _distance = Distance();

  // Great-circle distance in km between two coordinates (unit-independent,
  // unlike GeoCalculations which scales by the user's display units).
  static double distanceKm(LatLng a, LatLng b) => _distance.as(LengthUnit.Kilometer, a, b);

  // Builds the Open-Meteo forecast URL for pressure-level winds at a point.
  static Uri buildUrl(double lat, double lon, {String? apiKey}) {
    final hourly = <String>[];
    for (final l in _levelsHpa) {
      hourly.add('wind_speed_${l}hPa');
      hourly.add('wind_direction_${l}hPa');
      hourly.add('geopotential_height_${l}hPa');
    }
    final params = <String, String>{
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': hourly.join(','),
      'wind_speed_unit': 'kn',
      'forecast_days': '2',
      'timezone': 'UTC',
    };
    final key = apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      params['apikey'] = key;
    }
    return Uri.https(key != null && key.isNotEmpty ? customerHost : freeHost,
        '/v1/forecast', params);
  }

  // Encodes a direction (deg) + speed (kt) into the 4-char FB winds-aloft token
  // understood by [WindsAloft.decodeWind]. Returns '' when data is missing and
  // '9900' (light and variable) for calm/near-calm winds.
  static String encodeWind(int? dirDeg, double? speedKt) {
    if (dirDeg == null || speedKt == null) {
      return '';
    }
    final int spd = speedKt.round();
    if (spd < 5) {
      return '9900';
    }
    int d = (((dirDeg % 360) / 10).round()) % 36; // 0..35 tens of degrees
    int s = spd;
    if (s > 99) {
      // FB high-speed encoding: add 50 to the tens-of-degrees, subtract 100 kt.
      s -= 100;
      d += 50;
      if (s > 99) {
        s = 99; // clamp absurd speeds so the token stays 4 chars
      }
    }
    return '${d.toString().padLeft(2, '0')}${s.toString().padLeft(2, '0')}';
  }

  // Parses an Open-Meteo forecast body into a [WindsAloft] for [station].
  // [now] and [foreHours] select which forecast hour to use (default: the hour
  // nearest to now + 6 h, matching the app's 06H product). Returns null if the
  // payload cannot yield any usable level.
  static WindsAloft? parse(
    String station,
    String body, {
    DateTime? now,
    int foreHours = 6,
  }) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      AppLog.logMessage('OpenMeteoWinds.parse: bad JSON: $e');
      return null;
    }
    final hourly = json['hourly'];
    if (hourly is! Map) {
      return null;
    }
    final times = (hourly['time'] as List?)?.cast<String>();
    if (times == null || times.isEmpty) {
      return null;
    }

    final DateTime target =
        (now ?? DateTime.now().toUtc()).add(Duration(hours: foreHours));
    final int idx = _nearestHourIndex(times, target);
    if (idx < 0) {
      return null;
    }
    final DateTime validAt = DateTime.tryParse('${times[idx]}Z') ??
        DateTime.now().toUtc().add(Duration(hours: foreHours));

    // Build (altitudeFt, dir, speedKt) samples from each pressure level.
    final samples = <({double altFt, double dir, double spd})>[];
    for (final l in _levelsHpa) {
      final gh = _at(hourly['geopotential_height_${l}hPa'], idx);
      final ws = _at(hourly['wind_speed_${l}hPa'], idx);
      final wd = _at(hourly['wind_direction_${l}hPa'], idx);
      if (gh == null || ws == null || wd == null) {
        continue;
      }
      samples.add((altFt: gh * _mToFt, dir: wd, spd: ws));
    }
    if (samples.isEmpty) {
      return null;
    }
    samples.sort((a, b) => a.altFt.compareTo(b.altFt));

    final encoded = <String>[];
    for (final ft in slotFt) {
      final v = _interpolate(samples, ft.toDouble());
      encoded.add(v == null ? '' : encodeWind(v.$1.round(), v.$2));
    }

    return WindsAloft(
      station,
      validAt,
      now ?? DateTime.now().toUtc(),
      Weather.sourceInternet,
      encoded[0], encoded[1], encoded[2], encoded[3], encoded[4],
      encoded[5], encoded[6], encoded[7], encoded[8], encoded[9],
    );
  }

  // Fetches and parses winds for a coordinate. Returns null on any failure so
  // callers can silently fall back. [apiKey] is optional (free endpoint used
  // when absent).
  static Future<WindsAloft?> fetch(
    LatLng coordinate, {
    String? apiKey,
    String station = 'Open-Meteo',
    int foreHours = 6,
  }) async {
    final uri = buildUrl(coordinate.latitude, coordinate.longitude, apiKey: apiKey);
    try {
      final http.Response response =
          await Isolate.run(() => http.get(uri));
      if (response.statusCode != 200) {
        AppLog.logMessage('OpenMeteoWinds.fetch: HTTP ${response.statusCode}');
        return null;
      }
      return parse(station, response.body, foreHours: foreHours);
    } catch (e) {
      AppLog.logMessage('OpenMeteoWinds.fetch failed: $e');
      return null;
    }
  }

  static double? _at(dynamic list, int idx) {
    if (list is! List || idx < 0 || idx >= list.length) {
      return null;
    }
    final v = list[idx];
    if (v is num) {
      return v.toDouble();
    }
    return null;
  }

  // Index of the forecast hour nearest [target]. Returns -1 if none parse.
  static int _nearestHourIndex(List<String> times, DateTime target) {
    int best = -1;
    int bestDiff = 1 << 30;
    for (int i = 0; i < times.length; i++) {
      final t = DateTime.tryParse('${times[i]}Z');
      if (t == null) {
        continue;
      }
      final diff = (t.difference(target).inMinutes).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  // Linear interpolation of (dir, speed) at [targetFt] from altitude-sorted
  // samples. Direction uses shortest-arc interpolation. Returns null when the
  // target is outside the sampled range (caller leaves that slot empty; the
  // WindsAloft slot-fill logic then carries a neighbouring value).
  static (double, double)? _interpolate(
    List<({double altFt, double dir, double spd})> samples,
    double targetFt,
  ) {
    if (samples.isEmpty) {
      return null;
    }
    // At or below the lowest sample: use the lowest (surface winds).
    if (targetFt <= samples.first.altFt) {
      return (samples.first.dir, samples.first.spd);
    }
    if (targetFt >= samples.last.altFt) {
      return null; // above the data
    }
    for (int i = 0; i < samples.length - 1; i++) {
      final lo = samples[i];
      final hi = samples[i + 1];
      if (targetFt >= lo.altFt && targetFt <= hi.altFt) {
        final span = hi.altFt - lo.altFt;
        final f = span == 0 ? 0.0 : (targetFt - lo.altFt) / span;
        final spd = lo.spd + (hi.spd - lo.spd) * f;
        // Shortest-arc direction interpolation.
        double delta = hi.dir - lo.dir;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        double dir = (lo.dir + delta * f) % 360;
        if (dir < 0) dir += 360;
        return (dir, spd);
      }
    }
    return null;
  }
}
