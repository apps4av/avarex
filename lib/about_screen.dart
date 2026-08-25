import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yaml/yaml.dart';

import 'constants.dart';
import 'ofm/ofm_constants.dart';
import 'openaip/openaip_constants.dart';
import 'weather/flybrief_notams.dart';
import 'weather/open_meteo_winds.dart';
import 'weather/rainviewer_radar.dart';

/// A single third-party credit: what it is, the attribution/licence line, and
/// an optional link to the source.
class _Credit {
  final String name;
  final String detail;
  final String? url;
  const _Credit(this.name, this.detail, {this.url});
}

/// About / Credits screen.
///
/// Lists the third-party data sources and open-source software AvareX builds
/// on, with their attributions and licences. The full, auto-generated licence
/// text for every bundled package is available via the "Open-source licenses"
/// button (Flutter's built-in [showLicensePage], which enumerates every
/// dependency's LICENSE file).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Aeronautical and weather DATA providers. Attribution strings are the same
  // ones shown next to the data elsewhere in the app.
  static const List<_Credit> _dataSources = [
    _Credit(
      'FAA (US aeronautical data)',
      'US charts, airport/NASR data, procedures and obstacles. Public domain, courtesy of the Federal Aviation Administration.',
      url: 'https://www.faa.gov/',
    ),
    _Credit(
      'NWS / Aviation Weather Center',
      'METAR, TAF and US winds-aloft products. Public domain, courtesy of the US National Weather Service.',
      url: 'https://aviationweather.gov/',
    ),
    _Credit(
      'openFlightmaps',
      '${OfmConstants.attribution}. European VFR chart tiles and OFMX aeronautical data. Free for non-commercial use.',
      url: 'https://www.openflightmaps.org/',
    ),
    _Credit(
      'openAIP',
      '${OpenAipConstants.attribution}. Supplementary European airports, navaids, reporting points, airspace and obstacles.',
      url: 'https://www.openaip.net/',
    ),
    _Credit(
      'Open-Meteo',
      '${OpenMeteoWinds.attribution}. Global pressure-level winds aloft outside US coverage.',
      url: 'https://open-meteo.com/',
    ),
    _Credit(
      'FlyBrief',
      '${FlybriefNotams.attribution}. Per-country georeferenced European NOTAMs and obstacles.',
      url: 'https://flybrief.app/',
    ),
    _Credit(
      'RainViewer',
      '${RainViewerRadar.attribution}. Global, animated composite weather-radar mosaic (EU build).',
      url: 'https://www.rainviewer.com/',
    ),
    _Credit(
      'Iowa Environmental Mesonet',
      'US NEXRAD composite radar tiles. Courtesy of Iowa State University (US build radar).',
      url: 'https://mesonet.agron.iastate.edu/',
    ),
    _Credit(
      'AWS Terrain Tiles / Mapzen',
      'Terrarium elevation tiles used to build on-device terrain/GPWS data. Public domain / permissively licensed DEM sources.',
      url: 'https://registry.opendata.aws/terrain-tiles/',
    ),
    _Credit(
      'USGS The National Map',
      'US topographic base-map tiles. Public domain, courtesy of the US Geological Survey.',
      url: 'https://www.usgs.gov/',
    ),
    _Credit(
      'aip.aero',
      'Link-out index to official national AIP publications for European airports. No content is stored or redistributed.',
      url: 'https://aip.aero/',
    ),
  ];

  // Notable open-source SOFTWARE components. This is a highlighted subset; the
  // complete, authoritative licence list for every bundled package (including
  // transitive dependencies) is available via "Open-source licenses" below.
  static const List<_Credit> _software = [
    _Credit('Flutter & Dart', 'UI toolkit and language. BSD-3-Clause. © Google LLC.',
        url: 'https://flutter.dev/'),
    _Credit('flutter_map', 'Slippy-map rendering (charts, radar, overlays). BSD-3-Clause.',
        url: 'https://pub.dev/packages/flutter_map'),
    _Credit('flutter_map_marker_cluster', 'Marker clustering for the map. BSD-3-Clause.',
        url: 'https://pub.dev/packages/flutter_map_marker_cluster'),
    _Credit('vector_map_tiles / vector_tile_renderer', 'Vector MBTiles rendering. Apache-2.0.',
        url: 'https://pub.dev/packages/vector_map_tiles'),
    _Credit('mbtiles', 'MBTiles reader for offline charts. MIT.',
        url: 'https://pub.dev/packages/mbtiles'),
    _Credit('latlong2', 'Geodesic math. Apache-2.0 / BSD.',
        url: 'https://pub.dev/packages/latlong2'),
    _Credit('sqflite / sqlite3', 'On-device SQLite databases. MIT / BSD / public domain.',
        url: 'https://pub.dev/packages/sqflite'),
    _Credit('dio & http', 'HTTP clients for data downloads and APIs. MIT / BSD-3-Clause.',
        url: 'https://pub.dev/packages/dio'),
    _Credit('image', 'PNG decode/encode for radar and terrain tiles. Apache-2.0 / MIT.',
        url: 'https://pub.dev/packages/image'),
    _Credit('syncfusion_flutter_pdfviewer', 'PDF viewing (charts, manuals). Syncfusion Community License.',
        url: 'https://pub.dev/packages/syncfusion_flutter_pdfviewer'),
    _Credit('fl_chart', 'Terrain/altitude and performance charts. MIT.',
        url: 'https://pub.dev/packages/fl_chart'),
    _Credit('audioplayers', 'GPWS, traffic and runway audio alerts. MIT.',
        url: 'https://pub.dev/packages/audioplayers'),
    _Credit('flutter_secure_storage', 'Secure storage for user-supplied API keys. BSD-3-Clause.',
        url: 'https://pub.dev/packages/flutter_secure_storage'),
    _Credit('geolocator', 'GPS position. MIT.',
        url: 'https://pub.dev/packages/geolocator'),
    _Credit('flutter_bluetooth_serial_ble', 'Bluetooth ADS-B / GPS receivers. Various OSS.',
        url: 'https://pub.dev/packages/flutter_bluetooth_serial_ble'),
    _Credit('flutter_material_design_icons / Material Icons', 'Iconography. Apache-2.0.',
        url: 'https://pub.dev/packages/flutter_material_design_icons'),
    _Credit('toastification, dropdown_button2, auto_size_text, introduction_screen', 'Assorted UI widgets. MIT.',
        url: 'https://pub.dev/'),
    _Credit('archive, xml, csv, geojson_vi, point_in_polygon', 'Parsing and geometry utilities. MIT / Apache-2.0 / BSD.',
        url: 'https://pub.dev/'),
    _Credit('AI provider (Flight Intelligence)', 'User-supplied OpenAI-compatible endpoint. No AI service is bundled; requests use the pilot\'s own provider and key.',
        url: null),
  ];

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _creditTile(BuildContext context, _Credit c) {
    return ListTile(
      dense: true,
      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(c.detail, style: const TextStyle(fontSize: 12)),
      trailing: c.url == null
          ? null
          : Icon(Icons.open_in_new,
              size: 18, color: Theme.of(context).colorScheme.outline),
      onTap: c.url == null ? null : () => _open(c.url!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text('About & Credits'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Image.asset('assets/images/logo.png', width: 48, height: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AvareX',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      FutureBuilder(
                        future: rootBundle.loadString('pubspec.yaml'),
                        builder: (context, snapshot) {
                          String version = 'Unknown';
                          if (snapshot.hasData) {
                            final yaml = loadYaml(snapshot.data!);
                            version = yaml['version'].toString();
                          }
                          return Text('v$version',
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Theme.of(context).colorScheme.outline));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'A pilot\'s electronic flight bag, by Apps4Av. AvareX is built on '
              'the third-party data sources and open-source software credited '
              'below. Aeronautical and weather data is advisory only and is not '
              'a substitute for official, current sources.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          _section(context, 'Data sources'),
          for (final c in _dataSources) _creditTile(context, c),
          _section(context, 'Open-source software'),
          for (final c in _software) _creditTile(context, c),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              icon: const Icon(Icons.article_outlined),
              label: const Text('Open-source licenses'),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'AvareX',
                applicationLegalese: '© Apps4Av. Licensed under the project '
                    'license. Bundled package licenses are listed here.',
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
