// A decoded-METAR card with a VFR/IFR profile toggle and per-element threat
// coloring. Drop-in widget used on airport detail screens to complement the
// raw METAR text and flight-category badge. Uses only the raw METAR the app
// already holds (see MetarDecoder); no network calls.

import 'package:flutter/material.dart';

import '../storage.dart';
import 'metar.dart';
import 'metar_decoder.dart';

class DecodedMetarView extends StatefulWidget {
  final Metar metar;

  const DecodedMetarView({super.key, required this.metar});

  @override
  State<DecodedMetarView> createState() => _DecodedMetarViewState();
}

class _DecodedMetarViewState extends State<DecodedMetarView> {
  late WxProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = _readProfile();
  }

  // Read the persisted profile defensively: in contexts where Storage/settings
  // are not initialized (e.g. widget tests) fall back to IFR.
  WxProfile _readProfile() {
    try {
      return Storage().settings.getWeatherProfile() == 'VFR'
          ? WxProfile.vfr
          : WxProfile.ifr;
    } catch (_) {
      return WxProfile.ifr;
    }
  }

  void _setProfile(WxProfile p) {
    setState(() => _profile = p);
    try {
      Storage().settings.setWeatherProfile(p.label);
    } catch (_) {
      // Persistence unavailable (e.g. tests); selection still applies for the
      // current view.
    }
  }

  @override
  Widget build(BuildContext context) {
    final elements = MetarDecoder.decode(widget.metar.text, _profile);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Decoded METAR',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                // VFR / IFR threshold selector.
                SegmentedButton<WxProfile>(
                  segments: const [
                    ButtonSegment(value: WxProfile.vfr, label: Text('VFR')),
                    ButtonSegment(value: WxProfile.ifr, label: Text('IFR')),
                  ],
                  selected: {_profile},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setProfile(s.first),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Threat colors for ${_profile.label} operations. '
              'Advisory only — not a substitute for an official briefing.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(),
            for (final e in elements)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5, right: 8),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: e.threat.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(
                      width: 116,
                      child: Text(e.label,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Text(e.value,
                          style: TextStyle(color: e.threat.color)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
