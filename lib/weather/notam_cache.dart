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

      final notamElements = doc.findAllElements('event:NOTAM');
      if (notamElements.isEmpty) {
        return null;
      }

      final List<String> lines = [];
      for (final notam in notamElements) {
        String t(String name) =>
            notam.getElement(name)?.innerText.trim() ?? '';

        final number = t('event:number');
        final year = t('event:year');
        final type = t('event:type');
        final location = t('event:location');
        final effectiveStart = t('event:effectiveStart');
        final effectiveEnd = t('event:effectiveEnd');
        String body = t('event:text');

        // Translation block (FAA simpleText is the canonical pilot-format line).
        if (body.isEmpty) {
          for (final tr in notam.findAllElements('event:NOTAMTranslation')) {
            final st =
                tr.getElement('event:simpleText')?.innerText.trim() ?? '';
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
            .where((e) => e is xml.XmlElement && e.name.local == 'Event')
            .cast<xml.XmlElement>()
            .firstOrNull;
        if (eventEl != null) {
          for (final ext in eventEl.findAllElements('fnse:EventExtension')) {
            classification =
                ext.getElement('fnse:classification')?.innerText.trim() ?? '';
            accountId =
                ext.getElement('fnse:accountId')?.innerText.trim() ?? '';
            if (classification.isNotEmpty || accountId.isNotEmpty) break;
          }
        }

        // Header bits.
        final List<String> headerBits = [];
        final yy = year.length >= 2 ? year.substring(year.length - 2) : year;
        if (number.isNotEmpty || yy.isNotEmpty) {
          final id = yy.isNotEmpty ? '$yy/$number' : number;
          headerBits.add('NOTAM $id');
        } else {
          headerBits.add('NOTAM');
        }
        if (location.isNotEmpty) headerBits.add(location);
        if (type.isNotEmpty) headerBits.add('[$type]');
        if (classification.isNotEmpty) headerBits.add('($classification)');
        if (accountId.isNotEmpty) headerBits.add(accountId);

        // Effective range bit.
        final start = _formatNotamDate(effectiveStart);
        final end = _formatNotamDate(effectiveEnd);
        String range = '';
        if (start.isNotEmpty && end.isNotEmpty) {
          range = '$start-$end';
        } else if (start.isNotEmpty) {
          range = start;
        }

        // Compose a single line: collapse any internal whitespace/newlines.
        final parts = <String>[headerBits.join(' ')];
        if (range.isNotEmpty) parts.add(range);
        if (body.isNotEmpty) parts.add(body);

        final line = parts
            .join(' | ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        lines.add(line);
      }

      if (lines.isEmpty) return null;
      return lines.join('\n');
    } catch (_) {
      return null;
    }
  }

  /// Converts a 12-digit YYYYMMDDHHMM NOTAM timestamp into "YYYY-MM-DD HH:MMZ".
  /// Returns the input unchanged if it isn't 12 digits.
  String _formatNotamDate(String s) {
    if (s.length != 12 || int.tryParse(s) == null) {
      return s;
    }
    final yyyy = s.substring(0, 4);
    final mm = s.substring(4, 6);
    final dd = s.substring(6, 8);
    final hh = s.substring(8, 10);
    final mi = s.substring(10, 12);
    return '$yyyy-$mm-$dd $hh:${mi}Z';
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

      // ================================
      // 1. Get OAuth access token
      // ================================
      final tokenUrl = Uri.parse(
          "https://api-staging.cgifederal-aim.com/v1/auth/token");

      // Build Basic Auth header
      final creds = base64Encode(utf8.encode(
          "@@__faa_nms_api_client_id_secret__@@"));

      final tokenResponse = await http.post(
        tokenUrl,
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Authorization": "Basic $creds",
        },
        body: {
          "grant_type": "client_credentials",
        },
      );

      if (tokenResponse.statusCode != 200) {
        return;
      }

      final tokenJson = jsonDecode(tokenResponse.body);
      final accessToken = tokenJson["access_token"];

      // ================================
      // 2. Use access token to call NOTAM API
      // ================================
      final notamUrl = Uri.parse(
          "https://api-staging.cgifederal-aim.com/nmsapi/v1/notams?location=${airport.locationID}"
      );

      final notamResponse = await http.get(
        notamUrl,
        headers: {
          "Authorization": "Bearer $accessToken",
          "nmsResponseFormat": "AIXM",
        },
      );

      if (notamResponse.statusCode != 200) {
        return;
      }

      // this is ugly, parse is not used for NOTAMs

      final data = jsonDecode(notamResponse.body)["data"];
      if(data.isEmpty) {
        return;
      }
      final aixm = data["aixm"];
      if(aixm.isEmpty) {
        return;
      }
      for (var item in aixm) {
        String? txt = extractFormattedText(item);
        if (null != txt) {
          allNotams.add(txt);
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

