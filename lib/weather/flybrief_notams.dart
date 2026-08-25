// FlyBrief per-country NOTAM provider.
//
// AvareX's built-in NOTAM source is a US FAA API that returns nothing in
// Europe. FlyBrief (flybrief.app) publishes per-country, georeferenced NOTAM
// GeoJSON (polygons with altitudes, schedules, active-now flags) with no token,
// which fills the European NOTAM gap and can be stored for offline use.
//
// Data © OpenAIP contributors and national AIS, re-published by FlyBrief
// (CC BY-NC-SA 4.0). NOTAMs are advisory; always confirm against the official
// national briefing before flight.
//
// This file is PURE (no I/O) so it is unit-tested: country resolution, URL
// building, GeoJSON parsing, nearest filtering and one-line formatting. The
// network fetch and offline file storage live in flybrief_store.dart.

import 'dart:convert';
import 'dart:math' as math;

// A supported FlyBrief country: URL path segment, file slug, and a bounding box
// used to pick the country from a GPS position.
class FbCountry {
  final String iso2;
  final String path; // e.g. 'Germany' in /Airspace/EU/Germany/
  final String slug; // e.g. 'germany' in germany_notams.geojson
  final double minLat, maxLat, minLon, maxLon;

  const FbCountry(this.iso2, this.path, this.slug, this.minLat, this.maxLat,
      this.minLon, this.maxLon);

  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
}

// One parsed NOTAM with optional geometry for nearest filtering.
class FbNotam {
  final String id;
  final String category;
  final String text;
  final String raw;
  final String? lower; // altitude lower (al)
  final String? upper; // altitude upper (ah)
  final String? start;
  final String? end;
  final String? schedule;
  final bool perm;
  final bool activeNow;
  final bool highPriority;
  final double? radiusNm;
  // Representative point (centroid of geometry) for distance filtering; null
  // when the NOTAM has no precise geometry.
  final double? lat;
  final double? lon;

  const FbNotam({
    required this.id,
    required this.category,
    required this.text,
    required this.raw,
    this.lower,
    this.upper,
    this.start,
    this.end,
    this.schedule,
    this.perm = false,
    this.activeNow = false,
    this.highPriority = false,
    this.radiusNm,
    this.lat,
    this.lon,
  });

  // A compact, pilot-readable one-line summary matching the app's NOTAM style.
  String toLine() {
    final bits = <String>['NOTAM $id'];
    if (category.isNotEmpty) bits.add('[${category.toUpperCase()}]');
    if (activeNow) bits.add('(ACTIVE)');
    final header = bits.join(' ');

    final range = <String>[];
    if (perm) {
      range.add('PERM');
    } else {
      if (start != null && start!.isNotEmpty) range.add(_shortTime(start!));
      if (end != null && end!.isNotEmpty) range.add(_shortTime(end!));
    }
    final alt = <String>[];
    if (lower != null && lower!.isNotEmpty) alt.add(lower!);
    if (upper != null && upper!.isNotEmpty) alt.add(upper!);

    final parts = <String>[header];
    if (range.isNotEmpty) parts.add(range.join('-'));
    if (alt.isNotEmpty) parts.add(alt.join('/'));
    if (schedule != null && schedule!.isNotEmpty) parts.add('SKED ${schedule!}');
    if (text.isNotEmpty) parts.add(text);
    return parts.join(' | ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // Trims an ISO timestamp to "MM-DD HHmmZ" for compact display.
  static String _shortTime(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return iso;
    final u = t.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(u.month)}-${two(u.day)} ${two(u.hour)}${two(u.minute)}Z';
  }
}

class FlybriefNotams {
  FlybriefNotams._();

  static const String host = 'flybrief.app';
  static const String attribution =
      'NOTAMs © OpenAIP contributors & national AIS via FlyBrief (CC BY-NC-SA 4.0)';

  // Default search radius (nm) around a point when filtering NOTAMs.
  static const double defaultRadiusNm = 50;

  static const List<FbCountry> countries = [
    FbCountry('IE', 'Ireland', 'ireland', 51.2, 55.5, -10.6, -5.9),
    FbCountry('FR', 'France', 'france', 41.3, 51.2, -5.2, 9.7),
    FbCountry('ES', 'Spain', 'spain', 35.9, 43.9, -9.4, 4.4),
    FbCountry('PT', 'Portugal', 'portugal', 36.9, 42.2, -9.6, -6.1),
    FbCountry('BE', 'Belgium', 'belgium', 49.5, 51.6, 2.5, 6.4),
    FbCountry('NL', 'Netherlands', 'netherlands', 50.7, 53.7, 3.3, 7.3),
    FbCountry('DE', 'Germany', 'germany', 47.2, 55.1, 5.8, 15.1),
    FbCountry('CH', 'Switzerland', 'switzerland', 45.8, 47.9, 5.9, 10.6),
    FbCountry('AT', 'Austria', 'austria', 46.3, 49.1, 9.5, 17.2),
    FbCountry('IT', 'Italy', 'italy', 35.4, 47.1, 6.6, 18.6),
    FbCountry('SI', 'Slovenia', 'slovenia', 45.4, 46.9, 13.3, 16.7),
    FbCountry('HR', 'Croatia', 'croatia', 42.3, 46.6, 13.4, 19.5),
    FbCountry('BA', 'Bosnia', 'bosnia', 42.5, 45.3, 15.7, 19.7),
    FbCountry('RS', 'Serbia', 'serbia', 42.2, 46.2, 18.8, 23.0),
    FbCountry('HU', 'Hungary', 'hungary', 45.7, 48.6, 16.1, 22.9),
    FbCountry('CZ', 'Czechia', 'czechia', 48.5, 51.1, 12.1, 18.9),
    FbCountry('SK', 'Slovakia', 'slovakia', 47.7, 49.6, 16.8, 22.6),
    FbCountry('PL', 'Poland', 'poland', 49.0, 54.9, 14.1, 24.2),
    FbCountry('DK', 'Denmark', 'denmark', 54.5, 57.8, 8.0, 15.2),
    FbCountry('NO', 'Norway', 'norway', 57.9, 71.2, 4.5, 31.2),
    FbCountry('SE', 'Sweden', 'sweden', 55.3, 69.1, 11.0, 24.2),
    FbCountry('FI', 'Finland', 'finland', 59.7, 70.1, 20.5, 31.6),
    FbCountry('GR', 'Greece', 'greece', 34.8, 41.8, 19.3, 28.3),
    FbCountry('BG', 'Bulgaria', 'bulgaria', 41.2, 44.2, 22.3, 28.6),
    FbCountry('RO', 'Romania', 'romania', 43.6, 48.3, 20.2, 29.7),
    FbCountry('AL', 'Albania', 'albania', 39.6, 42.7, 19.2, 21.1),
    FbCountry('MK', 'NorthMacedonia', 'northmacedonia', 40.8, 42.4, 20.4, 23.0),
    FbCountry('TR', 'Turkey', 'turkey', 35.8, 42.1, 25.6, 44.8),
  ];

  static FbCountry? byIso(String iso2) {
    final u = iso2.trim().toUpperCase();
    for (final c in countries) {
      if (c.iso2 == u) return c;
    }
    return null;
  }

  // Picks the FlyBrief country whose bbox contains the point; if several match
  // (overlapping bboxes) the one whose center is nearest is chosen.
  static FbCountry? forPoint(double lat, double lon) {
    FbCountry? best;
    double bestD = double.infinity;
    for (final c in countries) {
      if (!c.contains(lat, lon)) continue;
      final cLat = (c.minLat + c.maxLat) / 2;
      final cLon = (c.minLon + c.maxLon) / 2;
      final d = (cLat - lat) * (cLat - lat) + (cLon - lon) * (cLon - lon);
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  // Builds the NOTAM GeoJSON URL for a country.
  static Uri notamUrl(FbCountry c) => Uri.https(
      host, '/Airspace/EU/${c.path}/${c.slug}_notams.geojson');

  // Builds the obstacles GeoJSON URL for a country.
  static Uri obstacleUrl(FbCountry c) => Uri.https(
      host, '/Airspace/EU/${c.path}/${c.slug}_obstacles.geojson');

  // Parses a FlyBrief NOTAM GeoJSON body into FbNotam records. Tolerates null
  // geometry (non-precise NOTAMs) and malformed features.
  static List<FbNotam> parse(String body) {
    final out = <FbNotam>[];
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return out;
    }
    final feats = json['features'];
    if (feats is! List) return out;
    for (final f in feats) {
      if (f is! Map) continue;
      final p = f['properties'];
      if (p is! Map) continue;
      final id = (p['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final (clat, clon) = _centroid(f['geometry']);
      out.add(FbNotam(
        id: id,
        category: (p['category'] ?? '').toString(),
        text: (p['text'] ?? '').toString(),
        raw: (p['raw'] ?? '').toString(),
        lower: p['al']?.toString(),
        upper: p['ah']?.toString(),
        start: p['start']?.toString(),
        end: p['end']?.toString(),
        schedule: p['schedule']?.toString(),
        perm: p['perm'] == true,
        activeNow: p['active_now'] == true,
        highPriority: p['hp'] == true,
        radiusNm: (p['radius_nm'] is num) ? (p['radius_nm'] as num).toDouble() : null,
        lat: clat,
        lon: clon,
      ));
    }
    return out;
  }

  // Filters to NOTAMs within [radiusNm] of (lat,lon). NOTAMs without geometry
  // are always included (country-wide / imprecise). Active NOTAMs sort first,
  // then by distance.
  static List<FbNotam> nearby(
    List<FbNotam> all,
    double lat,
    double lon, {
    double radiusNm = defaultRadiusNm,
  }) {
    final scored = <(double, FbNotam)>[];
    for (final n in all) {
      if (n.lat == null || n.lon == null) {
        scored.add((-1, n)); // no geometry -> always include, sort first
        continue;
      }
      final d = distanceNm(lat, lon, n.lat!, n.lon!);
      if (d <= radiusNm + (n.radiusNm ?? 0)) {
        scored.add((d, n));
      }
    }
    scored.sort((a, b) {
      if (a.$2.activeNow != b.$2.activeNow) {
        return a.$2.activeNow ? -1 : 1;
      }
      return a.$1.compareTo(b.$1);
    });
    return scored.map((e) => e.$2).toList();
  }

  // Formats a NOTAM list into the newline-separated text the NOTAM tab shows.
  static String format(List<FbNotam> notams) =>
      notams.map((n) => n.toLine()).join('\n\n');

  // Great-circle distance in nautical miles.
  static double distanceNm(double lat1, double lon1, double lat2, double lon2) {
    const double rNm = 3440.065;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return rNm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180.0;

  // Centroid (mean vertex) of a GeoJSON geometry; returns (null,null) when the
  // geometry is null or unusable.
  static (double?, double?) _centroid(dynamic geometry) {
    if (geometry is! Map) return (null, null);
    final coords = geometry['coordinates'];
    final pts = <List<double>>[];
    _collectPoints(coords, pts);
    if (pts.isEmpty) return (null, null);
    double sLon = 0, sLat = 0;
    for (final pt in pts) {
      sLon += pt[0];
      sLat += pt[1];
    }
    return (sLat / pts.length, sLon / pts.length);
  }

  static void _collectPoints(dynamic node, List<List<double>> out) {
    if (node is! List) return;
    if (node.length >= 2 && node[0] is num && node[1] is num) {
      out.add([(node[0] as num).toDouble(), (node[1] as num).toDouble()]);
      return;
    }
    for (final child in node) {
      _collectPoints(child, out);
    }
  }
}
