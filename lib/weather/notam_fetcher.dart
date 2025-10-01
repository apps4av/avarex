import 'dart:async';
import 'package:html/parser.dart' as html show parse;
import 'package:http/http.dart' as http;

/// Fetch NOTAMs from U.S. government sources and return a list of messages.
///
/// Primary source: Aviation Weather Center (aviationweather.gov)
/// Fallback: FAA DINS (notams.faa.gov)
class GovNotamService {
  static const String _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 AvareX';

  /// Returns NOTAM messages for an ICAO airport, e.g., "KBVY".
  static Future<List<String>> getNotams(String icao,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final String code = icao.trim().toUpperCase();
    if (code.length < 3) {
      throw ArgumentError("Expected an ICAO code like 'KBVY'.");
    }

    // Try AWC raw endpoints first
    final List<Uri> awcUris = [
      Uri.parse(
          'https://www.aviationweather.gov/api/data/notams?format=raw&loc=$code'),
      Uri.parse(
          'https://www.aviationweather.gov/api/data/notams?format=raw&ids=$code'),
      // Legacy HTML page variant that sometimes returns raw content
      Uri.parse('https://www.aviationweather.gov/notam?format=raw&ids=$code'),
    ];

    for (final Uri uri in awcUris) {
      try {
        final http.Response resp = await http
            .get(uri, headers: _headers)
            .timeout(timeout);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final List<String> messages = _parseAwcRaw(resp.body);
          if (messages.isNotEmpty) {
            return messages;
          }
        }
      } catch (_) {
        // try next
      }
    }

    // Fallback: FAA DINS web interface (HTML in <pre>)
    try {
      final Uri dinsUri = Uri.parse(
          'https://www.notams.faa.gov/dinsQueryWeb/queryRetrievalByICAOAction.do?retrieveLocId=$code&actionType=notamRetrievalByICAOs&formatType=ICAO');
      final http.Response resp =
          await http.get(dinsUri, headers: _headers).timeout(timeout);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final List<String> messages = _parseDinsHtml(resp.body);
        if (messages.isNotEmpty) {
          return messages;
        }
      }
    } catch (_) {
      // ignore
    }

    return <String>[];
  }

  static Map<String, String> get _headers => <String, String>{
        'User-Agent': _userAgent,
        'Accept': 'text/plain, text/html, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Connection': 'close',
      };

  // Parse raw NOTAM text as returned by AWC raw endpoints.
  static List<String> _parseAwcRaw(String text) {
    if (text.isEmpty) {
      return <String>[];
    }

    final String normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) {
      return <String>[];
    }

    final String lower = normalized.toLowerCase();
    if (lower.contains('<html') || lower.contains('<pre')) {
      // Looks like HTML, not raw
      return <String>[];
    }

    // Prefer splitting on blank lines to keep wrapped NOTAMs together
    final List<String> chunks = normalized
        .split(RegExp('\n\s*\n'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    if (chunks.length > 1) {
      return chunks.map(_squashWhitespace).toList(growable: false);
    }

    // Fallback: heuristic grouping by lines
    final List<String> lines = normalized
        .split('\n')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();

    final List<String> kept = <String>[];
    final List<String> buffer = <String>[];

    void flush() {
      if (buffer.isNotEmpty) {
        kept.add(_squashWhitespace(buffer.join(' ')));
        buffer.clear();
      }
    }

    for (final String line in lines) {
      if (_looksLikeNotamStart(line)) {
        flush();
        buffer.add(line);
      } else {
        buffer.add(line);
      }
    }
    flush();
    return kept;
  }

  // Parse NOTAMs from FAA DINS HTML (content typically inside <pre>)
  static List<String> _parseDinsHtml(String htmlText) {
    if (htmlText.isEmpty) {
      return <String>[];
    }

    final document = html.parse(htmlText);
    final preElements = document.getElementsByTagName('pre');
    String text;
    if (preElements.isNotEmpty) {
      text = preElements.first.text;
    } else {
      text = document.body?.text ?? htmlText;
    }

    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) {
      return <String>[];
    }

    final List<String> chunks = text
        .split(RegExp('\n\s*\n'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    final List<String> messages =
        chunks.map(_squashWhitespace).toList(growable: false);

    // Remove boilerplate
    final List<String> filtered = <String>[];
    for (final String msg in messages) {
      final String upper = msg.toUpperCase();
      if (upper.contains('NO NOTAMS')) {
        continue;
      }
      if (upper.startsWith('DISCLAIMER')) {
        continue;
      }
      if (upper.startsWith('QUERY') || upper.startsWith('REQUEST')) {
        continue;
      }
      filtered.add(msg);
    }
    return filtered;
  }

  static String _squashWhitespace(String s) =>
      s.replaceAll(RegExp('\n+'), ' ').replaceAll(RegExp('\s+'), ' ').trim();

  static bool _looksLikeNotamStart(String line) {
    final String l = line.trim();
    if (l.isEmpty) {
      return false;
    }
    if (l.startsWith('!')) {
      return true; // Domestic NOTAM format
    }
    if (RegExp(r'^[A-Z]{4}\b').hasMatch(l)) {
      return true; // Starts with ICAO
    }
    if (l.startsWith('Q)') || l.startsWith('A)')) {
      return true; // ICAO Q-line blocks
    }
    return false;
  }
}

