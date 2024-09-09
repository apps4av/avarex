
import 'package:flutter/material.dart';

import 'chart.dart';


class DownloadManager {

  final List<Chart> _charts = [];

  final ValueNotifier<int> downloads = ValueNotifier<int>(0);

  Chart? _findChart(Chart chart) {
    for (Chart c in _charts) {
      if (c.filename == chart.filename) {
        return c;
      }
    }
    return null;
  }

  void download(Chart chart, bool nextCycle) {
    if (null != _findChart(chart)) {
      // already downloading
      return;
    }
    chart.enabled = false;
    chart.progress.value = 0;
    _charts.add(chart);
    chart.download.download(chart, nextCycle, (c, progress) {
      Chart? c = _findChart(chart);
      if (null != c) {
        c.progress.value = progress;
        if (0 == progress) {
          c.subtitle = "Downloading";
          c.enabled = false;
        }
        else if (50 == progress) {
          c.subtitle = "Installing";
          c.enabled = false;
        }
        else if (100 == progress) {
          c.subtitle = "Download Success";
          c.enabled = true;
          _charts.remove(c);
          downloads.value++;
        }
        else if (progress < 0) {
          c.subtitle = "Download Failed";
          c.enabled = true;
          _charts.remove(c);
        }
      }
    });
  }

  void cancel(Chart chart) {
    Chart? c = _findChart(chart);
    if(null != c) {
      c.download.cancel();
      c.progress.value = 0;
      c.enabled = true;
      _charts.remove(c);
    }
  }

  void delete(Chart chart) {
    if (null != _findChart(chart)) {
      // already deleting
      return;
    }
    chart.enabled = false;
    chart.progress.value = 0;
    _charts.add(chart);
    chart.download.delete(chart, (c, progress) {
      Chart? c = _findChart(chart);
      if (null != c) {
        c.progress.value = progress;
        if(0 == progress) {
          chart.subtitle = "Uninstalling";
          chart.enabled = false;
        }
        else if(100 == progress) {
          chart.enabled = true;
          _charts.remove(c);
          downloads.value++;
        }
        else if(progress < 0) {
          chart.enabled = true;
          _charts.remove(c);
        }
      }
    });
  }

  int total() {
    return _charts.length;
  }

}