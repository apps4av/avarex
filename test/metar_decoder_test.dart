import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/weather/metar_decoder.dart';

void main() {
  WxElement? byLabel(List<WxElement> els, String label) {
    for (final e in els) {
      if (e.label == label) return e;
    }
    return null;
  }

  group('MetarDecoder.decode elements', () {
    test('decodes wind with gusts', () {
      const raw = 'METAR EGLL 240920Z 10012G22KT 9999 BKN030 18/11 Q1021';
      final wind = byLabel(MetarDecoder.decode(raw, WxProfile.vfr), 'Wind');
      expect(wind, isNotNull);
      expect(wind!.value, 'From 100° at 12 kt, gusting 22 kt');
    });

    test('decodes variable and calm wind', () {
      final vrb = byLabel(
          MetarDecoder.decode('METAR KXYZ 010000Z VRB03KT 10SM CLR 20/10 A2992',
              WxProfile.vfr),
          'Wind');
      expect(vrb!.value, 'Variable at 3 kt');
      final calm = byLabel(
          MetarDecoder.decode('METAR KXYZ 010000Z 00000KT 10SM CLR 20/10 A2992',
              WxProfile.vfr),
          'Wind');
      expect(calm!.value, 'Calm');
    });

    test('converts m/s wind to knots', () {
      final wind = byLabel(
          MetarDecoder.decode('METAR ULLI 010000Z 09010MPS 9999 SCT040 05/01 Q1013',
              WxProfile.vfr),
          'Wind');
      expect(wind!.value, 'From 090° at 19 kt'); // 10 m/s ≈ 19.4 kt
    });

    test('decodes statute-mile and metric visibility', () {
      final sm = byLabel(
          MetarDecoder.decode('METAR KJFK 010000Z 09010KT 1 1/2SM BR OVC004 12/11 A2990',
              WxProfile.ifr),
          'Visibility');
      expect(sm!.value, '1.5 SM');

      final metric = byLabel(
          MetarDecoder.decode('METAR EDDF 010000Z 09010KT 0800 FG OVC002 05/05 Q1013',
              WxProfile.ifr),
          'Visibility');
      expect(metric!.value, '800 m');

      final cavok = byLabel(
          MetarDecoder.decode('METAR LOWW 010000Z 09010KT CAVOK 20/07 Q1021',
              WxProfile.vfr),
          'Visibility');
      expect(cavok!.value, 'CAVOK (ceiling and visibility OK)');
    });

    test('decodes ceiling and reports sky clear', () {
      final ceil = byLabel(
          MetarDecoder.decode('METAR KABC 010000Z 09010KT 5SM OVC012 10/05 A2990',
              WxProfile.vfr),
          'Ceiling');
      expect(ceil!.value, '1200 ft AGL');

      final clear = byLabel(
          MetarDecoder.decode('METAR KABC 010000Z 09010KT 10SM CLR 10/05 A2990',
              WxProfile.vfr),
          'Ceiling');
      expect(clear!.value, 'No ceiling (sky clear)');
    });

    test('decodes present weather phenomena', () {
      final wx = byLabel(
          MetarDecoder.decode('METAR KABC 010000Z 09010KT 2SM +TSRA BKN008 18/17 A2990',
              WxProfile.vfr),
          'Weather');
      expect(wx, isNotNull);
      expect(wx!.value.toLowerCase(), contains('thunderstorm'));
      expect(wx.value.toLowerCase(), contains('rain'));
      expect(wx.threat, WxThreat.hazard);
    });

    test('decodes temperature/dewpoint with negative values', () {
      final t = byLabel(
          MetarDecoder.decode('METAR ENGM 010000Z 09010KT 9999 SCT030 M02/M05 Q1013',
              WxProfile.vfr),
          'Temp / Dewpoint');
      expect(t!.value, '-2°C / -5°C (spread 3°C)');
    });

    test('decodes QNH and altimeter pressure', () {
      final q = byLabel(
          MetarDecoder.decode('METAR EGLL 010000Z 09010KT 9999 SCT030 18/11 Q1021',
              WxProfile.vfr),
          'Pressure');
      expect(q!.value, 'QNH 1021 hPa');

      final a = byLabel(
          MetarDecoder.decode('METAR KJFK 010000Z 09010KT 10SM SCT030 18/11 A2992',
              WxProfile.vfr),
          'Pressure');
      expect(a!.value, 'Altimeter 29.92 inHg');
    });
  });

  group('MetarDecoder profile-dependent threat coloring', () {
    // 2500 ft ceiling, 4 SM: MVFR. Caution for VFR, fine for IFR.
    const marginal = 'METAR KABC 010000Z 09010KT 4SM BR OVC025 12/09 A2990';

    test('MVFR ceiling/vis is caution for VFR but none for IFR', () {
      final vfr = MetarDecoder.decode(marginal, WxProfile.vfr);
      final ifr = MetarDecoder.decode(marginal, WxProfile.ifr);

      expect(byLabel(vfr, 'Flight category')!.threat, WxThreat.caution);
      expect(byLabel(ifr, 'Flight category')!.threat, WxThreat.none);

      expect(byLabel(vfr, 'Ceiling')!.threat, WxThreat.caution);
      expect(byLabel(ifr, 'Ceiling')!.threat, WxThreat.none);

      expect(byLabel(vfr, 'Visibility')!.threat, WxThreat.caution);
      expect(byLabel(ifr, 'Visibility')!.threat, WxThreat.none);
    });

    test('same wind rated harsher under VFR thresholds', () {
      const windy = 'METAR KABC 010000Z 09018KT 10SM SCT050 20/05 A2992';
      final vfr = byLabel(MetarDecoder.decode(windy, WxProfile.vfr), 'Wind');
      final ifr = byLabel(MetarDecoder.decode(windy, WxProfile.ifr), 'Wind');
      expect(vfr!.threat, WxThreat.caution); // ≥15 kt VFR caution
      expect(ifr!.threat, WxThreat.none); // <25 kt IFR fine
    });

    test('low IFR conditions are hazard even for IFR profile', () {
      const lowIfr = 'METAR KABC 010000Z 09010KT 1/4SM FG VV002 10/10 A2990';
      final ifr = MetarDecoder.decode(lowIfr, WxProfile.ifr);
      expect(byLabel(ifr, 'Visibility')!.threat, WxThreat.hazard);
      expect(byLabel(ifr, 'Ceiling')!.threat, WxThreat.hazard);
    });
  });

  test('always emits a flight-category element first', () {
    final els = MetarDecoder.decode(
        'METAR EGLL 240920Z 10012KT 9999 BKN050 18/11 Q1021', WxProfile.vfr);
    expect(els.first.label, 'Flight category');
    expect(els.first.value, 'VFR');
  });
}
