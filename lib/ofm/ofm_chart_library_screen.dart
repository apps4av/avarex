import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';

import '../storage.dart';
import '../utils/pdf_viewer.dart';
import 'ofm_constants.dart';
import 'ofm_manifest.dart';
import 'ofm_manifest_store.dart';

class OfmChartLibraryScreen extends StatefulWidget {
  const OfmChartLibraryScreen({super.key});

  @override
  State<OfmChartLibraryScreen> createState() => _OfmChartLibraryScreenState();
}

class _OfmChartLibraryScreenState extends State<OfmChartLibraryScreen> {
  late Future<List<OfmInstalledProduct>> _charts;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _charts = OfmManifestStore(Storage().dataDir).load().then((manifest) async {
      final charts = <OfmInstalledProduct>[];
      for (final product in manifest.products.where((item) => item.type == 'pdf')) {
        if (await File(product.localPath).exists()) charts.add(product);
      }
      charts.sort((a, b) => '${a.region}:${a.cycle}:${a.name}'.compareTo('${b.region}:${b.cycle}:${b.name}'));
      return charts;
    });
  }

  Future<void> _remove(OfmInstalledProduct product) async {
    await OfmManifestStore(Storage().dataDir).removeProduct(product);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OFM VFR Chart Sheets')),
      body: FutureBuilder<List<OfmInstalledProduct>>(
        future: _charts,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final charts = snapshot.data!;
          if (charts.isEmpty) {
            return const Center(child: Text('No OFM PDF chart sheets are installed.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Card(child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Document view—not GPS-referenced.\n${OfmConstants.disclaimer}\n${OfmConstants.attribution}'),
              )),
              for (final chart in charts)
                Card(child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: Text('${chart.name} — ${chart.details}'),
                  subtitle: Text('${chart.region} • AIRAC ${chart.cycle}${chart.byteSize == null ? '' : ' • ${(chart.byteSize! / 1048576).toStringAsFixed(1)} MiB'}'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PdfViewer(chart.localPath, title: '${chart.name} — ${chart.details}', notice: 'OFM chart sheet • not GPS-referenced'),
                  )),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _remove(chart)),
                )),
            ],
          );
        },
      ),
    );
  }
}
