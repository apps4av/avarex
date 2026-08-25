// Plain-English METAR decoding and selectable VFR/IFR threat coloring.
//
// This complements the existing FAA flight-category coloring (Metar.getColor)
// with a per-operation threat view inspired by route-briefing tools: the pilot
// picks an operating profile (VFR vs IFR) and key METAR elements are colored by
// thresholds appropriate to that profile, alongside a human-readable decode.
//
// All inputs come from data AvareX already holds (the raw METAR string). No
// network calls, no third-party services.

import 'package:flutter/material.dart';

import 'metar.dart';

// Severity of a decoded weather element under the selected profile.
enum WxThreat { none, caution, hazard }

extension WxThreatColor on WxThreat {
  // Colors mirror the app's existing green/amber/red weather semantics and
  // stay legible on both light and dark themes.
  Color get color {
    switch (this) {
      case WxThreat.none:
        return const Color(0xFF2E7D32); // green 800
      case WxThreat.caution:
        return const Color(0xFFF9A825); // amber 800
      case WxThreat.hazard:
        return const Color(0xFFC62828); // red 800
    }
  }
}

// Operating profile that governs threat thresholds.
enum WxProfile { vfr, ifr }

extension WxProfileLabel on WxProfile {
  String get label => this == WxProfile.vfr ? 'VFR' : 'IFR';
}

// A single decoded, plain-English METAR element with a threat level.
class WxElement {
  final String label; // e.g. "Wind", "Visibility"
  final String value; // plain-English decode, e.g. "From 090° at 12 kt"
  final WxThreat threat;

  const WxElement(this.label, this.value, this.threat);
}

// Threshold set for a profile. Ceilings in feet AGL, visibility in statute
// miles, wind/gust in knots. Values below/above these flip caution/hazard.
class WxThresholds {
  final double ceilingHazardFt; // at/below → hazard
  final double ceilingCautionFt; // at/below → caution
  final double visHazardSM; // below → hazard
  final double visCautionSM; // below → caution
  final double windCautionKt; // steady wind at/above → caution
  final double windHazardKt; // steady wind at/above → hazard
  final double gustCautionKt; // gust at/above → caution
  final double gustHazardKt; // gust at/above → hazard

  const WxThresholds({
    required this.ceilingHazardFt,
    required this.ceilingCautionFt,
    required this.visHazardSM,
    required this.visCautionSM,
    required this.windCautionKt,
    required this.windHazardKt,
    required this.gustCautionKt,
    required this.gustHazardKt,
  });

  // Defaults chosen to be conservative and easy to reason about:
  // - VFR: keys off VFR/MVFR boundaries (3 SM / 1000 ft are hard IFR limits
  //   for a VFR pilot; below the VFR minima of 5 SM / 3000 ft is caution).
  // - IFR: keys off approach-minima-scale numbers (200 ft / 0.5 SM hazard,
  //   below ~600 ft / 1 SM caution) plus higher wind tolerance.
  static const WxThresholds vfr = WxThresholds(
    ceilingHazardFt: 1000,
    ceilingCautionFt: 3000,
    visHazardSM: 3,
    visCautionSM: 5,
    windCautionKt: 15,
    windHazardKt: 25,
    gustCautionKt: 20,
    gustHazardKt: 30,
  );

  static const WxThresholds ifr = WxThresholds(
    ceilingHazardFt: 200,
    ceilingCautionFt: 600,
    visHazardSM: 0.5,
    visCautionSM: 1,
    windCautionKt: 25,
    windHazardKt: 35,
    gustCautionKt: 30,
    gustHazardKt: 40,
  );

  static WxThresholds forProfile(WxProfile profile) =>
      profile == WxProfile.vfr ? vfr : ifr;
}

class MetarDecoder {
  MetarDecoder._();

  static const double _metersPerSM = 1609.344;

  // Decodes a raw METAR into an ordered list of plain-English elements with
  // per-element threat levels for the selected profile. Elements that cannot
  // be parsed are simply omitted (never guessed).
  static List<WxElement> decode(String raw, WxProfile profile) {
    final thresholds = WxThresholds.forProfile(profile);
    final report = raw.trim();
    final elements = <WxElement>[];

    // Flight category (reuses the existing FAA-category logic).
    final category = Metar.getCategory(report);
    elements.add(WxElement('Flight category', category,
        _categoryThreat(category, profile)));

    final wind = _decodeWind(report, thresholds);
    if (wind != null) elements.add(wind);

    final vis = _decodeVisibility(report, thresholds);
    if (vis != null) elements.add(vis);

    final ceiling = _decodeCeiling(report, thresholds);
    if (ceiling != null) elements.add(ceiling);

    final wx = _decodePhenomena(report);
    if (wx != null) elements.add(wx);

    final temp = _decodeTemp(report);
    if (temp != null) elements.add(temp);

    final qnh = _decodePressure(report);
    if (qnh != null) elements.add(qnh);

    return elements;
  }

  // MVFR/IFR/LIFR matter more to a VFR pilot than an IFR one.
  static WxThreat _categoryThreat(String category, WxProfile profile) {
    if (profile == WxProfile.vfr) {
      switch (category) {
        case 'VFR':
          return WxThreat.none;
        case 'MVFR':
          return WxThreat.caution;
        default: // IFR / LIFR
          return WxThreat.hazard;
      }
    } else {
      switch (category) {
        case 'VFR':
        case 'MVFR':
          return WxThreat.none;
        case 'IFR':
          return WxThreat.caution;
        default: // LIFR
          return WxThreat.hazard;
      }
    }
  }

  static WxElement? _decodeWind(String report, WxThresholds t) {
    // Calm wind is a special all-zero token; handle before the general regex
    // (which would otherwise decode it as "From 000° at 0 kt").
    if (RegExp(r'(?<=\s)00000(KT|MPS)(?=\s)').hasMatch(' $report ')) {
      return const WxElement('Wind', 'Calm', WxThreat.none);
    }
    final RegExp wind = RegExp(
        r'(?<dir>\d{3}|VRB)P?(?<speed>\d{2,3})(G(P)?(?<gust>\d{2,3}))?(?<units>KT|MPS)');
    for (final token in report.split(' ')) {
      final m = wind.firstMatch(token);
      if (m == null) continue;
      final dir = m.namedGroup('dir')!;
      final unit = m.namedGroup('units')!;
      double speed = double.parse(m.namedGroup('speed')!);
      final gustStr = m.namedGroup('gust');
      double? gust = gustStr == null ? null : double.parse(gustStr);
      // Normalize m/s to knots for threshold comparison and display.
      if (unit == 'MPS') {
        speed = speed * 1.943844;
        if (gust != null) gust = gust * 1.943844;
      }
      final dirText = dir == 'VRB' ? 'Variable' : 'From $dir°';
      final gustText = gust == null ? '' : ', gusting ${gust.round()} kt';
      final value = '$dirText at ${speed.round()} kt$gustText';

      WxThreat threat = WxThreat.none;
      if (speed >= t.windHazardKt ||
          (gust != null && gust >= t.gustHazardKt)) {
        threat = WxThreat.hazard;
      } else if (speed >= t.windCautionKt ||
          (gust != null && gust >= t.gustCautionKt)) {
        threat = WxThreat.caution;
      }
      return WxElement('Wind', value, threat);
    }
    return null;
  }

  static WxElement? _decodeVisibility(String report, WxThresholds t) {
    double? visSM;
    String? text;

    if (report.contains('CAVOK')) {
      visSM = 6;
      text = 'CAVOK (ceiling and visibility OK)';
    } else {
      // US statute-mile form: "10SM", "1 1/2SM", "1/2SM", "M1/4SM".
      final smMatch = RegExp(
              r'(?<![\d/])(M|P)?((?<int>\d{1,2})\s+)?(?<frac>\d/\d)?(?<whole>\d{1,2})?SM')
          .allMatches(report);
      for (final m in smMatch) {
        double v = 0;
        final intPart = m.namedGroup('int');
        final frac = m.namedGroup('frac');
        final whole = m.namedGroup('whole');
        if (intPart != null) v += double.tryParse(intPart) ?? 0;
        if (frac != null) {
          final p = frac.split('/');
          if (p.length == 2) {
            final n = double.tryParse(p[0]);
            final d = double.tryParse(p[1]);
            if (n != null && d != null && d != 0) v += n / d;
          }
        }
        if (whole != null && frac == null && intPart == null) {
          v += double.tryParse(whole) ?? 0;
        }
        if (v > 0 || frac != null) {
          visSM = v;
          text = '${_trimNum(v)} SM';
          break;
        }
      }
      // ICAO 4-digit metre form: "9999", "0800". Only when no SM form present.
      if (visSM == null) {
        final mMatch =
            RegExp(r'(?<=\s)(?<vis>\d{4})(?<dir>[NSEW]{1,2})?(?=\s)')
                .firstMatch(' $report ');
        if (mMatch != null) {
          final meters = double.tryParse(mMatch.namedGroup('vis')!);
          if (meters != null) {
            visSM = meters / _metersPerSM;
            if (meters >= 9999) {
              text = '10 km or more';
            } else if (meters >= 5000) {
              text = '${(meters / 1000).round()} km';
            } else {
              text = '${meters.round()} m';
            }
          }
        }
      }
    }

    if (visSM == null || text == null) return null;

    WxThreat threat = WxThreat.none;
    if (visSM < t.visHazardSM) {
      threat = WxThreat.hazard;
    } else if (visSM < t.visCautionSM) {
      threat = WxThreat.caution;
    }
    return WxElement('Visibility', text, threat);
  }

  static WxElement? _decodeCeiling(String report, WxThresholds t) {
    final int? ceilingFt = Metar.getCeilingFtFromReport(report);
    if (ceilingFt == null) {
      // No BKN/OVC/VV layer → no ceiling. Report sky-clear when explicit.
      if (RegExp(r'\b(CAVOK|CLR|SKC|NSC|NCD)\b').hasMatch(report)) {
        return const WxElement('Ceiling', 'No ceiling (sky clear)', WxThreat.none);
      }
      return null;
    }
    WxThreat threat = WxThreat.none;
    if (ceilingFt <= t.ceilingHazardFt) {
      threat = WxThreat.hazard;
    } else if (ceilingFt <= t.ceilingCautionFt) {
      threat = WxThreat.caution;
    }
    return WxElement('Ceiling', '$ceilingFt ft AGL', threat);
  }

  // Decode significant present-weather phenomena into plain English. Any
  // present weather beyond plain rain is at least a caution.
  static WxElement? _decodePhenomena(String report) {
    const Map<String, String> descriptors = {
      'MI': 'shallow', 'BC': 'patches of', 'DR': 'low drifting', 'BL': 'blowing',
      'SH': 'showers of', 'TS': 'thunderstorm', 'FZ': 'freezing',
    };
    const Map<String, String> phenomena = {
      'DZ': 'drizzle', 'RA': 'rain', 'SN': 'snow', 'SG': 'snow grains',
      'IC': 'ice crystals', 'PL': 'ice pellets', 'GR': 'hail',
      'GS': 'small hail', 'UP': 'unknown precip', 'BR': 'mist', 'FG': 'fog',
      'FU': 'smoke', 'VA': 'volcanic ash', 'DU': 'widespread dust',
      'SA': 'sand', 'HZ': 'haze', 'PY': 'spray', 'PO': 'dust whirls',
      'SQ': 'squalls', 'FC': 'funnel cloud', 'SS': 'sandstorm', 'DS': 'duststorm',
    };
    final parts = <String>[];
    bool hazard = false;
    // Match tokens like -SHRA, +TSRA, VCFG, FZFG, BR.
    final tokenRe = RegExp(
        r'^(?<int>[-+]|VC)?(?<groups>(MI|BC|DR|BL|SH|TS|FZ|DZ|RA|SN|SG|IC|PL|GR|GS|UP|BR|FG|FU|VA|DU|SA|HZ|PY|PO|SQ|FC|SS|DS)+)$');
    for (final token in report.split(' ')) {
      final m = tokenRe.firstMatch(token);
      if (m == null) continue;
      final intensityRaw = m.namedGroup('int');
      final groups = m.namedGroup('groups')!;
      // Split the concatenated 2-letter codes.
      final codes = RegExp(r'..').allMatches(groups).map((e) => e.group(0)!);
      final words = <String>[];
      for (final c in codes) {
        if (descriptors.containsKey(c)) {
          words.add(descriptors[c]!);
          if (c == 'TS' || c == 'FZ') hazard = true;
        } else if (phenomena.containsKey(c)) {
          words.add(phenomena[c]!);
          if (['GR', 'GS', 'FC', 'SS', 'DS', 'VA', 'PL'].contains(c)) {
            hazard = true;
          }
        }
      }
      if (words.isEmpty) continue;
      String intensity = '';
      if (intensityRaw == '-') {
        intensity = 'light ';
      } else if (intensityRaw == '+') {
        intensity = 'heavy ';
        hazard = true;
      } else if (intensityRaw == 'VC') {
        intensity = 'in the vicinity: ';
      }
      parts.add('$intensity${words.join(' ')}');
    }
    if (parts.isEmpty) return null;
    return WxElement('Weather', _capitalize(parts.join(', ')),
        hazard ? WxThreat.hazard : WxThreat.caution);
  }

  static WxElement? _decodeTemp(String report) {
    final m = RegExp(r'(?<=\s)(M?\d{2})/(M?\d{2})(?=\s)').firstMatch(' $report ');
    if (m == null) return null;
    int parse(String s) =>
        s.startsWith('M') ? -int.parse(s.substring(1)) : int.parse(s);
    final temp = parse(m.group(1)!);
    final dew = parse(m.group(2)!);
    final spread = temp - dew;
    // Small temp/dew spread → fog/low-cloud risk → caution.
    final threat = spread <= 2 ? WxThreat.caution : WxThreat.none;
    return WxElement('Temp / Dewpoint', '$temp°C / $dew°C (spread $spread°C)',
        threat);
  }

  static WxElement? _decodePressure(String report) {
    final q = RegExp(r'(?<=\s)Q(\d{4})(?=\s)').firstMatch(' $report ');
    if (q != null) {
      return WxElement('Pressure', 'QNH ${int.parse(q.group(1)!)} hPa',
          WxThreat.none);
    }
    final a = RegExp(r'(?<=\s)A(\d{4})(?=\s)').firstMatch(' $report ');
    if (a != null) {
      final v = a.group(1)!;
      return WxElement('Pressure',
          'Altimeter ${v.substring(0, 2)}.${v.substring(2)} inHg',
          WxThreat.none);
    }
    return null;
  }

  static String _trimNum(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
