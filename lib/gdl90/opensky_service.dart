import 'dart:async';
import 'dart:convert';

import 'package:avaremp/gdl90/opensky_credentials.dart';
import 'package:avaremp/gdl90/traffic_report_message.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/app_log.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Internet (ADS-B) traffic provider backed by the OpenSky Network REST API.
///
/// ADVISORY ONLY. This is crowdsourced ADS-B with coverage gaps and latency
/// (state vectors update on the order of 5-10 s plus network delay). It is a
/// supplement for situational awareness when no hardware ADS-B receiver is
/// connected. It must never be used for separation or collision avoidance;
/// connected GDL90 hardware traffic remains the real-time source.
///
/// Auth: OpenSky uses the OAuth2 client-credentials flow. The pilot supplies
/// their own client_id/secret (see [OpenSkyCredentials]); a bearer token is
/// obtained and cached until shortly before expiry. Data is fetched for a
/// bounding box around ownship via GET /states/all and fed into the shared
/// [TrafficCache], so it renders through the existing traffic display.
class OpenSkyService {
  OpenSkyService._();
  static final OpenSkyService instance = OpenSkyService._();

  static const String _tokenUrl =
      'https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token';
  static const String _statesUrl = 'https://opensky-network.org/api/states/all';

  static const String attribution = 'Traffic © The OpenSky Network';

  // GDL90 traffic report message type id (cosmetic; used only in the log).
  static const int _trafficType = 20;
  static const double _mToFt = 3.28084;

  // Half-size of the bounding box (degrees) fetched around ownship. ~0.9 deg
  // lat is ~54 NM; keeps the query small and within the traffic puck window.
  static const double _boxHalfDeg = 0.9;

  final OpenSkyCredentials _credentials = const OpenSkyCredentials();

  String? _token;
  DateTime _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(0);
  bool _fetching = false;
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Timestamp (UTC) of the last successful state fetch, for the UI banner.
  DateTime? lastSuccess;

  /// Obtains a valid bearer token, refreshing via client-credentials when the
  /// cached one is missing or within 30 s of expiry. Returns null on failure.
  Future<String?> _ensureToken(String clientId, String clientSecret) async {
    if (_token != null &&
        DateTime.now().isBefore(_tokenExpiry.subtract(const Duration(seconds: 30)))) {
      return _token;
    }
    try {
      final resp = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'client_credentials',
          'client_id': clientId,
          'client_secret': clientSecret,
        },
      );
      if (resp.statusCode != 200) {
        AppLog.logMessage('OpenSky token HTTP ${resp.statusCode}');
        return null;
      }
      final Map<String, dynamic> data = jsonDecode(resp.body);
      final token = data['access_token'] as String?;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 1800;
      if (token == null || token.isEmpty) return null;
      _token = token;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
      return _token;
    } catch (e) {
      AppLog.logMessage('OpenSky token failed: $e');
      return null;
    }
  }

  /// Verifies credentials by requesting a token. Returns null on success, or a
  /// short human-readable error message. Used by the settings "Test" button.
  Future<String?> testCredentials(String clientId, String clientSecret) async {
    _token = null; // force refresh
    final token = await _ensureToken(clientId, clientSecret);
    return token == null
        ? 'Could not authenticate. Check the client ID and secret.'
        : null;
  }

  /// Fetches traffic around ownship if the feature is active. Self-throttles to
  /// [minInterval] (OpenSky updates no faster than ~5-10 s and credits are
  /// limited). Silently no-ops when disabled, unconfigured, or without a fix.
  Future<void> poll({Duration minInterval = const Duration(seconds: 12)}) async {
    if (_fetching) return;
    if (DateTime.now().difference(_lastFetch) < minInterval) return;

    if (!await _credentials.isActive()) return;

    final pos = Storage().position;
    if (Gps.isPositionCloseToZero(pos)) return; // no usable fix yet

    _fetching = true;
    _lastFetch = DateTime.now();
    try {
      final clientId = await _credentials.readClientId();
      final clientSecret = await _credentials.readClientSecret();
      final token = await _ensureToken(clientId, clientSecret);
      if (token == null) return;

      final double lamin = pos.latitude - _boxHalfDeg;
      final double lamax = pos.latitude + _boxHalfDeg;
      final double lomin = pos.longitude - _boxHalfDeg;
      final double lomax = pos.longitude + _boxHalfDeg;
      final uri = Uri.parse(
          '$_statesUrl?lamin=$lamin&lomin=$lomin&lamax=$lamax&lomax=$lomax');

      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 401) {
        _token = null; // token rejected; drop so next poll refreshes
        AppLog.logMessage('OpenSky states 401 (token dropped)');
        return;
      }
      if (resp.statusCode != 200) {
        AppLog.logMessage('OpenSky states HTTP ${resp.statusCode}');
        return;
      }
      final Map<String, dynamic> data = jsonDecode(resp.body);
      final List<dynamic> states = (data['states'] as List?) ?? const [];
      var count = 0;
      for (final s in states) {
        final msg = _toTraffic(s);
        if (msg != null) {
          Storage().trafficCache.putTraffic(msg);
          count++;
        }
      }
      lastSuccess = DateTime.now().toUtc();
      if (count > 0) {
        // Refresh the traffic layer + distances/alerts like a GPS tick would.
        Storage().trafficCache.updateTrafficDistancesAndAlerts();
      }
    } catch (e) {
      AppLog.logMessage('OpenSky poll failed: $e');
    } finally {
      _fetching = false;
    }
  }

  /// Maps one OpenSky state-vector array into a [TrafficReportMessage], or null
  /// when it lacks a usable position. Array layout per the OpenSky REST docs:
  /// 0 icao24, 1 callsign, 5 longitude, 6 latitude, 7 baro_altitude(m),
  /// 8 on_ground, 9 velocity(m/s), 10 true_track(deg), 11 vertical_rate(m/s),
  /// 13 geo_altitude(m).
  TrafficReportMessage? _toTraffic(dynamic s) {
    if (s is! List || s.length < 12) return null;
    final double? lon = _toD(s[5]);
    final double? lat = _toD(s[6]);
    if (lon == null || lat == null) return null;

    final msg = TrafficReportMessage(_trafficType);
    final String icaoHex = (s[0] as String?)?.trim() ?? '';
    msg.icao = icaoHex.isEmpty ? 0 : (int.tryParse(icaoHex, radix: 16) ?? 0);
    msg.callSign = ((s[1] as String?) ?? '').trim();
    msg.coordinates = LatLng(lat, lon);
    final bool onGround = s[8] == true;
    msg.airborne = !onGround;
    // Prefer geometric altitude; fall back to barometric. Meters -> feet.
    final double? altM = _toD(s.length > 13 ? s[13] : null) ?? _toD(s[7]);
    msg.altitude = altM == null ? 0 : altM * _mToFt;
    msg.velocity = _toD(s[9]) ?? 0; // m/s (matches TrafficReportMessage)
    msg.heading = _toD(s[10]) ?? 0; // true track, deg
    msg.verticalSpeed = _toD(s[11]) ?? 0; // m/s (matches TrafficPainter usage)
    msg.addressType = 0;
    return msg;
  }

  static double? _toD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
