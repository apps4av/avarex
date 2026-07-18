import 'package:avaremp/chart/chart.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

/// A non-dismissible dialog that downloads a list of required charts/databases
/// one after another and blocks the user from continuing until they all finish.
///
/// Used during onboarding to automatically fetch the DatabasesX package plus the
/// Sectional and Plates for the region the device is currently located in.
class ChartDownloadDialog extends StatefulWidget {
  final List<Chart> charts;
  final String title;
  final String message;

  const ChartDownloadDialog({
    super.key,
    required this.charts,
    this.title = "Downloading Required Data",
    this.message =
        "AvareX is downloading the databases and charts for your region. Please keep the app open until this finishes.",
  });

  @override
  State<ChartDownloadDialog> createState() => _ChartDownloadDialogState();
}

class _ChartDownloadDialogState extends State<ChartDownloadDialog> {
  int _index = 0;
  bool _failed = false;
  bool _done = false;
  Chart? _current;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startNext());
  }

  void _startNext() {
    if (_index >= widget.charts.length) {
      _finishAll();
      return;
    }
    _current = widget.charts[_index];
    _current!.progress.addListener(_onProgress);
    setState(() {
      _failed = false;
    });
    // DownloadManager dedupes by filename, so this is a no-op if a download for
    // this chart is already in flight.
    Storage().downloadManager.download(_current!, false, false);
  }

  void _retry() {
    setState(() {
      _failed = false;
    });
    Storage().downloadManager.download(_current!, false, false);
  }

  void _onProgress() {
    if (_done) {
      return;
    }
    final int v = _current!.progress.value;
    if (v >= 100) {
      _current!.progress.removeListener(_onProgress);
      _current!.progress.value = 0;
      _index++;
      _startNext();
    }
    else if (v < 0) {
      setState(() {
        _failed = true;
      });
    }
    else {
      setState(() {});
    }
  }

  Future<void> _finishAll() async {
    _done = true;
    await Storage().checkChartsExist();
    await Storage().checkDataExpiry();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _current?.progress.removeListener(_onProgress);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int total = widget.charts.length;
    final int v = _current?.progress.value ?? 0;
    final double currentFraction = (v > 0 && v < 100) ? v / 100.0 : 0.0;
    final double overall =
        total == 0 ? 1.0 : (_index + currentFraction) / total;

    String itemName = _current?.name ?? "";
    String status;
    if (_failed) {
      status = "Download failed. Please check your internet connection and try again.";
    }
    else if (v <= 0) {
      status = "Preparing $itemName\u2026";
    }
    else if (v < 50) {
      status = "Downloading $itemName\u2026";
    }
    else {
      status = "Installing $itemName\u2026";
    }

    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(widget.message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (!_failed) ...[
                LinearProgressIndicator(value: overall),
                const SizedBox(height: 8),
                Text(
                  "Item ${(_index + 1).clamp(1, total)} of $total",
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 12),
              ],
              Text(status, textAlign: TextAlign.center),
              if (_failed) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _retry,
                  child: const Text("Retry"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
