import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather_cams.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Shows the latest picture from every camera of one FAA WeatherCams site.
/// Pull down to reload the pictures; tap a picture to see it full screen.
class WeatherCamsScreen extends StatefulWidget {
  final WeatherCamSite site;

  const WeatherCamsScreen({super.key, required this.site});

  /// Opens the pictures of [site] on top of the current screen.
  static Future<void> open(BuildContext context, WeatherCamSite site) {
    return Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => WeatherCamsScreen(site: site)));
  }

  @override
  State<WeatherCamsScreen> createState() => _WeatherCamsScreenState();
}

class _WeatherCamsScreenState extends State<WeatherCamsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await WeatherCams.loadImages(widget.site);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  static String _age(DateTime time) {
    final Duration d = DateTime.now().toUtc().difference(time);
    if (d.inMinutes < 1) {
      return "just now";
    }
    if (d.inMinutes < 60) {
      return "${d.inMinutes} min ago";
    }
    if (d.inHours < 48) {
      return "${d.inHours} h ago";
    }
    return "${d.inDays} d ago";
  }

  static String _utc(DateTime time) {
    final String h = time.hour.toString().padLeft(2, '0');
    final String m = time.minute.toString().padLeft(2, '0');
    return "$h:${m}Z";
  }

  Widget _picture(WeatherCamImage image, {BoxFit fit = BoxFit.fitWidth}) {
    return CachedNetworkImage(
      imageUrl: image.url,
      cacheManager: FileCacheManager().documentsCacheManager,
      fit: fit,
      placeholder: (context, url) => const AspectRatio(
        aspectRatio: 4 / 3,
        child: Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (context, url, error) => const AspectRatio(
        aspectRatio: 4 / 3,
        child: Center(child: Text("Unable to load this picture")),
      ),
    );
  }

  void _openFull(WeatherCamCamera cam, WeatherCamImage image) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text("${widget.site.name} - ${cam.label}",
              style: const TextStyle(fontSize: 16)),
        ),
        backgroundColor: Colors.black,
        body: Center(
          child: InteractiveViewer(
            maxScale: 6,
            child: _picture(image, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  Widget _camera(WeatherCamCamera cam) {
    final WeatherCamImage? image = widget.site.images[cam.cameraId];
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? status = cam.outOfOrder
        ? "Out of order"
        : cam.inMaintenance
            ? "In maintenance"
            : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                if (cam.bearing != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Transform.rotate(
                      angle: cam.bearing! * 3.1415926535 / 180,
                      child: Icon(Icons.navigation, size: 18, color: scheme.primary),
                    ),
                  ),
                Expanded(
                  child: Text(cam.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (image != null)
                  Text("${_age(image.time)}  ${_utc(image.time)}",
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
              ],
            ),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(status, style: TextStyle(color: scheme.error, fontSize: 12)),
            ),
          if (image != null)
            InkWell(
              onTap: () => _openFull(cam, image),
              child: _picture(image),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final WeatherCamSite site = widget.site;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // only cameras that have a picture; the rest cannot show anything
    final List<WeatherCamCamera> withImages =
        site.cameras.where((c) => site.images.containsKey(c.cameraId)).toList();
    final List<Widget> children = [
      if (withImages.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              site.inMaintenance ? "Site is in maintenance" : "No pictures available",
              style: TextStyle(color: scheme.outline),
            ),
          ),
        ),
      for (final WeatherCamCamera cam in withImages) _camera(cam),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text("Source: FAA WeatherCams (weathercams.faa.gov)",
            style: TextStyle(fontSize: 11, color: scheme.outline)),
      ),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final WeatherCamSite site = widget.site;
    final String title = "${site.name}"
        "${site.identifier.isNotEmpty ? " (${site.identifier})" : ""}"
        "${site.state.isNotEmpty ? ", ${site.state}" : ""}";
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 16))),
      body: _body(),
    );
  }
}
