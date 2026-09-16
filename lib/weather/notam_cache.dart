import 'dart:convert';
import 'dart:typed_data';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

import 'notam.dart';

class NotamCache extends WeatherCache {

  // Auth is on the host without /nmsapi. Data calls use the /nmsapi base path.
  static const String _authUrl = "https://api-nms.aim.faa.gov/v1/auth/token";
  static const String _notamsHost = "api-nms.aim.faa.gov";
  static const String _notamsPath = "/nmsapi/v1/notams";

  String? _accessToken;
  DateTime? _accessTokenExpiresAt;

  NotamCache(super.url, super.dbCall);

  /// Parses an AIXM NOTAM XML string and returns a one-line, user-readable
  /// summary for each <event:NOTAM> contained in it (one NOTAM per line).
  /// Returns null if no NOTAMs are found.
  ///
  /// Example single-line output:
  ///
  ///   NOTAM 26/15 U82 [N] (DOM) BOI | 2026-05-02 14:54Z-2026-06-01 06:00Z | RWY 18/36 REDL U/S
  String? extractFormattedText(String xmlString) {
    try {
      final doc = xml.XmlDocument.parse(xmlString);

      final notamElements = _elementsByLocalName(doc, 'NOTAM');
      if (notamElements.isEmpty) {
        return null;
      }

      final List<String> lines = [];
      for (final notam in notamElements) {
        String t(String name) => _childText(notam, name);

        final number = t('number');
        final year = t('year');
        final type = t('type');
        final location = t('location');
        final effectiveStart = t('effectiveStart');
        final effectiveEnd = t('effectiveEnd');
        String body = t('text');

        // Translation block (FAA simpleText is the canonical pilot-format line).
        if (body.isEmpty) {
          for (final tr in _elementsByLocalName(notam, 'NOTAMTranslation')) {
            final st = _childText(tr, 'simpleText');
            if (st.isNotEmpty) {
              body = st;
              break;
            }
          }
        }

        // Optional FNSE extension fields (siblings of textNOTAM under the Event).
        String classification = '';
        String accountId = '';
        final eventEl = notam.ancestors
            .whereType<xml.XmlElement>()
            .where((e) => e.name.local == 'Event')
            .firstOrNull;
        if (eventEl != null) {
          for (final ext in _elementsByLocalName(eventEl, 'EventExtension')) {
            classification = _childText(ext, 'classification');
            accountId = _childText(ext, 'accountId');
            if (classification.isNotEmpty || accountId.isNotEmpty) break;
          }
        }

        final line = _formatNotamLine(
          number: number,
          year: year,
          type: type,
          location: location,
          classification: classification,
          accountId: accountId,
          effectiveStart: effectiveStart,
          effectiveEnd: effectiveEnd,
          body: body,
        );
        if (line.isNotEmpty) {
          lines.add(line);
        }
      }

      if (lines.isEmpty) return null;
      return lines.join('\n');
    } catch (_) {
      return null;
    }
  }

  String? _extractGeoJsonText(Map<dynamic, dynamic> feature) {
    try {
      final properties = feature['properties'];
      if (properties is! Map) {
        return null;
      }
      final core = properties['coreNOTAMData'];
      if (core is! Map) {
        return null;
      }
      final notam = core['notam'];
      if (notam is! Map) {
        return null;
      }

      String body = (notam['text'] ?? '').toString().trim();
      final translations = core['notamTranslation'];
      if (body.isEmpty && translations is List) {
        for (final tr in translations) {
          if (tr is! Map) {
            continue;
          }
          final st = (tr['simpleText'] ?? '').toString().trim();
          if (st.isNotEmpty) {
            body = st;
            break;
          }
        }
      }

      return _formatNotamLine(
        number: (notam['number'] ?? '').toString(),
        year: (notam['year'] ?? '').toString(),
        type: (notam['type'] ?? '').toString(),
        location: (notam['location'] ?? '').toString(),
        classification: (notam['classification'] ?? '').toString(),
        accountId: (notam['accountId'] ?? '').toString(),
        effectiveStart: (notam['effectiveStart'] ?? '').toString(),
        effectiveEnd: (notam['effectiveEnd'] ?? '').toString(),
        body: body,
      );
    } catch (_) {
      return null;
    }
  }

  String _formatNotamLine({
    required String number,
    required String year,
    required String type,
    required String location,
    required String classification,
    required String accountId,
    required String effectiveStart,
    required String effectiveEnd,
    required String body,
  }) {
    final List<String> headerBits = [];
    if (number.contains('/')) {
      headerBits.add('NOTAM $number');
    } else {
      final yy = year.length >= 2 ? year.substring(year.length - 2) : year;
      if (number.isNotEmpty || yy.isNotEmpty) {
        final id = yy.isNotEmpty ? '$yy/$number' : number;
        headerBits.add('NOTAM $id');
      } else {
        headerBits.add('NOTAM');
      }
    }
    if (location.isNotEmpty) headerBits.add(location);
    if (type.isNotEmpty) headerBits.add('[$type]');
    if (classification.isNotEmpty) headerBits.add('($classification)');
    if (accountId.isNotEmpty) headerBits.add(accountId);

    final start = _formatNotamDate(effectiveStart);
    final end = _formatNotamDate(effectiveEnd);
    String range = '';
    if (start.isNotEmpty && end.isNotEmpty) {
      range = '$start-$end';
    } else if (start.isNotEmpty) {
      range = start;
    }

    final parts = <String>[headerBits.join(' ')];
    if (range.isNotEmpty) parts.add(range);
    if (body.isNotEmpty) parts.add(body);

    return parts
        .join(' | ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Converts a NOTAM timestamp into "YYYY-MM-DD HH:MMZ".
  /// Accepts 12-digit YYYYMMDDHHMM and ISO-8601 values from NMS-API.
  String _formatNotamDate(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.length == 12 && int.tryParse(trimmed) != null) {
      final yyyy = trimmed.substring(0, 4);
      final mm = trimmed.substring(4, 6);
      final dd = trimmed.substring(6, 8);
      final hh = trimmed.substring(8, 10);
      final mi = trimmed.substring(10, 12);
      return '$yyyy-$mm-$dd $hh:${mi}Z';
    }
    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      final utc = parsed.toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${utc.year}-${two(utc.month)}-${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)}Z';
    }
    return trimmed;
  }

  String _childText(xml.XmlElement parent, String localName) {
    return parent.childElements
        .where((e) => e.name.local == localName)
        .firstOrNull
        ?.innerText
        .trim() ?? '';
  }

  Iterable<xml.XmlElement> _elementsByLocalName(xml.XmlNode node, String localName) {
    return node.descendants
        .whereType<xml.XmlElement>()
        .where((e) => e.name.local == localName);
  }

  Future<String?> _getAccessToken() async {
    final now = DateTime.now().toUtc();
    if (_accessToken != null &&
        _accessTokenExpiresAt != null &&
        now.isBefore(_accessTokenExpiresAt!)) {
      return _accessToken;
    }

    final creds = base64Encode(utf8.encode(
        "@@__faa_nms_api_client_id_secret__@@"));

    final tokenResponse = await http.post(
      Uri.parse(_authUrl),
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": "Basic $creds",
      },
      body: {
        "grant_type": "client_credentials",
      },
    );

    if (tokenResponse.statusCode != 200) {
      _accessToken = null;
      _accessTokenExpiresAt = null;
      return null;
    }

    final tokenJson = jsonDecode(tokenResponse.body);
    if (tokenJson is! Map) {
      return null;
    }
    final accessToken = tokenJson["access_token"]?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    final expiresRaw = tokenJson["expires_in"];
    final expiresIn = expiresRaw is int
        ? expiresRaw
        : int.tryParse(expiresRaw?.toString() ?? "") ?? 1799;
    // Renew a minute early; production tokens last about 30 minutes.
    final ttl = expiresIn > 60 ? expiresIn - 60 : expiresIn;

    _accessToken = accessToken;
    _accessTokenExpiresAt = now.add(Duration(seconds: ttl));
    return _accessToken;
  }

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {

  }

  // Download and parse, override because this is a POST
  @override
  Future<void> download([String? argument]) async {
    if(null == argument) {
      return;
    }

    Destination? airport = await MainDatabaseHelper.db.findAirport(argument);
    if(null == airport) {
      return;
    }

    try {

      // Store results
      List<String> allNotams = [];

      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        return;
      }

      final notamUrl = Uri.https(
        _notamsHost,
        _notamsPath,
        {"location": airport.locationID},
      );

      final notamResponse = await http.get(
        notamUrl,
        headers: {
          "Authorization": "Bearer $accessToken",
          "nmsResponseFormat": "GEOJSON",
        },
      );

      if (notamResponse.statusCode == 401) {
        _accessToken = null;
        _accessTokenExpiresAt = null;
        return;
      }

      if (notamResponse.statusCode != 200) {
        return;
      }

      // this is ugly, parse is not used for NOTAMs

      final decoded = jsonDecode(notamResponse.body);
      if (decoded is! Map) {
        return;
      }
      final data = decoded["data"];
      if (data is! Map) {
        return;
      }

      final geojson = data["geojson"];
      if (geojson is List) {
        for (final item in geojson) {
          if (item is! Map) {
            continue;
          }
          final txt = _extractGeoJsonText(item);
          if (txt != null && txt.isNotEmpty) {
            allNotams.add(txt);
          }
        }
      }

      if (allNotams.isEmpty) {
        final aixm = data["aixm"];
        if (aixm is List) {
          for (final item in aixm) {
            if (item is! String) {
              continue;
            }
            String? txt = extractFormattedText(item);
            if (null != txt) {
              allNotams.add(txt);
            }
          }
        }
      }

      if(allNotams.isEmpty) {
        return;
      }
      String all = allNotams.join("\n\n");
      Notam notam = Notam(argument,
          DateTime.now().toUtc().add(
              const Duration(minutes: Constants.weatherUpdateTimeMin)),
          DateTime.now().toUtc(),
          Weather.sourceInternet, all);

      await WeatherDatabaseHelper.db.addNotam(notam);

    }
    catch(e) {
      if(Storage().gpsInternal) {
        // no internet if GPS external, so do not log errors
        Storage().setException("Unable to download NOTAM: $e");
      }
      return;
    }
    await initialize();
  }

  // wait till we get it either from cache or from internet
  Future<Weather?> getSync(String? station) async {
    Weather? w = super.get(station);
    if(null == w) {
      // if not found, download
      await download(station);
      w = super.get(station);
    }
    return w;
  }
}
