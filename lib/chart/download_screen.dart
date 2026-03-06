
import 'package:avaremp/utils/faa_dates.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';
import 'chart.dart';
import '../constants.dart';
import 'download.dart';


const int _stateAbsentNone = 0;
const int _stateAbsentDownload = 1;
const int _stateCurrentNone = 2;
const int _stateCurrentDownload = 3;
const int _stateCurrentDelete = 4;
const int _stateExpiredNone = 5;
const int _stateExpiredDownload = 6;
const int _stateExpiredDelete = 7;

const Color _absentColor = Constants.chartAbsentColor;
const Color _currentColor = Constants.chartCurrentColor;
const Color _expiredColor = Constants.chartExpiredColor;

const IconData _absentIcon = Icons.cloud_download_outlined;
const IconData _downloadedIcon = Icons.check_circle;
const IconData _downloadIcon = Icons.download;
const IconData _deleteIcon = Icons.delete_forever;

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});
  @override
  DownloadScreenState createState() => DownloadScreenState();
}

class DownloadScreenState extends State<DownloadScreen> {

  bool _nextCycle = false;
  bool _backupServer = false;

  @override
  void initState() {
    super.initState();
    for (ChartCategory cg in _allCharts) {
      for (Chart chart in cg.charts) {
        _getChartStateFromLocal(chart);
        chart.progress.addListener(_progressListener);
      }
    }
    Storage().downloadManager.downloads.addListener(_finishedListener);
  }

  @override
  void dispose() {
    Storage().downloadManager.downloads.removeListener(_finishedListener);
    for (ChartCategory cg in _allCharts) {
      for (Chart chart in cg.charts) {
        chart.progress.removeListener(_progressListener);
      }
    }
    super.dispose();
  }

  void _progressListener() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateCategory();
          setState(() {});
        }
      });
    }
  }

  void _finishedListener() {
    for (ChartCategory cg in _allCharts) {
      for (Chart chart in cg.charts) {
        _getChartStateFromLocal(chart);
      }
    }
  }

  void _showMap() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog.fullscreen(
          child: Container(
            color: Colors.black,
              child: Stack(
                children:[
                  Center(child:InteractiveViewer(child: Image.asset('assets/images/regions.jpeg'))),
                  Align(alignment: Alignment.topRight, child: IconButton(icon: const Icon(Icons.close, size: 36), onPressed: () {Navigator.of(context).pop();}))
                ]
              ),
            ),
          );
      },
    );
  }

  Widget _buildStatusSummary() {
    int currentCount = 0;
    int expiredCount = 0;
    int pendingDownload = 0;
    int pendingDelete = 0;
    int activeDownloads = 0;

    for (ChartCategory cg in _allCharts) {
      for (Chart chart in cg.charts) {
        if (chart.progress.value > 0 && chart.progress.value < 100) {
          activeDownloads++;
        }
        switch (chart.state) {
          case _stateCurrentNone:
            currentCount++;
            break;
          case _stateCurrentDownload:
            currentCount++;
            pendingDownload++;
            break;
          case _stateCurrentDelete:
            currentCount++;
            pendingDelete++;
            break;
          case _stateExpiredNone:
            expiredCount++;
            break;
          case _stateExpiredDownload:
            expiredCount++;
            pendingDownload++;
            break;
          case _stateExpiredDelete:
            expiredCount++;
            pendingDelete++;
            break;
          case _stateAbsentDownload:
            pendingDownload++;
            break;
        }
      }
    }

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusTile(Icons.check_circle, currentCount, "Current", _currentColor),
                _buildStatusTile(Icons.warning, expiredCount, "Expired", _expiredColor),
                _buildStatusTile(Icons.download, pendingDownload, "To Download", Colors.blue),
                _buildStatusTile(Icons.delete, pendingDelete, "To Delete", Colors.red),
              ],
            ),
            if (activeDownloads > 0 || pendingDownload > 0 || pendingDelete > 0) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              if (activeDownloads > 0)
                Text(
                  "Downloading $activeDownloads item${activeDownloads > 1 ? 's' : ''}...",
                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                )
              else
                Text(
                  "Tap Download to process ${pendingDownload + pendingDelete} item${(pendingDownload + pendingDelete) > 1 ? 's' : ''}",
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTile(IconData icon, int count, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text("$count", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }

  IconData _getCategoryIcon(String title) {
    switch (title) {
      default:
        return Icons.folder;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Downloads"),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: "View Regions Map",
            onPressed: _showMap,
          ),
          TextButton(
            onPressed: _download,
            child: const Text("Download"),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: TextButton(
              onPressed: _update,
              child: const Text("Update"),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusSummary(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _allCharts.length,
              itemBuilder: (context, index) {
                final category = _allCharts[index];
                int installedCount = category.charts.where((c) =>
                  c.state == _stateCurrentNone || c.state == _stateCurrentDownload || c.state == _stateCurrentDelete ||
                  c.state == _stateExpiredNone || c.state == _stateExpiredDownload || c.state == _stateExpiredDelete
                ).length;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ExpansionTile(
                    leading: Icon(_getCategoryIcon(category.title), color: category.color),
                    title: Text(category.title, style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      "$installedCount / ${category.charts.length} installed",
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                    ),
                    trailing: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: category.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          children: _buildExpandableContent(index),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                DropdownButton<bool>(
                  value: _nextCycle,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: false, child: Text("This Cycle")),
                    DropdownMenuItem(value: true, child: Text("Next Cycle")),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _nextCycle = value;
                      });
                    }
                  },
                ),
                const SizedBox(width: 16),
                DropdownButton<bool>(
                  value: _backupServer,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: false, child: Text("Main Server")),
                    DropdownMenuItem(value: true, child: Text("Backup Server")),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _backupServer = value;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildExpandableContent(int index) {
    List<Widget> columnContent = [];
    ChartCategory chartCategory = _allCharts[index];

    for (Chart chart in chartCategory.charts) {
      columnContent.add(
          ValueListenableBuilder<int>(
            valueListenable: chart.progress,
            builder: (context, value, _) {
            if(value >= 100) {
              chart.progress.value = 0;
              _getChartStateFromLocal(chart);
            }

            bool isDownloading = value > 0;
            bool isQueued = chart.state == _stateAbsentDownload ||
                            chart.state == _stateCurrentDownload ||
                            chart.state == _stateExpiredDownload;
            bool isDeleting = chart.state == _stateCurrentDelete ||
                              chart.state == _stateExpiredDelete;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: isQueued ? Colors.blue.withAlpha(20) :
                       isDeleting ? Colors.red.withAlpha(20) : null,
                borderRadius: BorderRadius.circular(8),
                border: isQueued || isDeleting ? Border.all(
                  color: isQueued ? Colors.blue.withAlpha(100) : Colors.red.withAlpha(100),
                ) : null,
              ),
              child: ListTile(
                dense: true,
                title: Text(chart.name, style: TextStyle(fontWeight: isQueued || isDeleting ? FontWeight.w600 : FontWeight.normal)),
                subtitle: chart.subtitle.isNotEmpty
                    ? Text(chart.subtitle, style: TextStyle(fontSize: 11, color: chart.color))
                    : Text("Not installed", style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                trailing: isDownloading
                    ? SizedBox(
                        width: 40,
                        height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: value.toDouble() / 100,
                              strokeWidth: 3,
                              backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => chart.download.cancel(),
                            ),
                          ],
                        ),
                      )
                    : Icon(chart.icon, color: chart.color, size: 22),
                leading: _buildActionIndicator(chart),
                enabled: chart.enabled,
                onTap: () {
                  setState(() {
                    _chartTouched(chart);
                  });
                },
              ),
            );
          })
        );
    }
    return columnContent;
  }

  Widget? _buildActionIndicator(Chart chart) {
    if (chart.state == _stateAbsentDownload ||
        chart.state == _stateCurrentDownload ||
        chart.state == _stateExpiredDownload) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(30),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.download, color: Colors.blue, size: 16),
      );
    } else if (chart.state == _stateCurrentDelete ||
               chart.state == _stateExpiredDelete) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(30),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.delete, color: Colors.red, size: 16),
      );
    }
    return null;
  }

  void _updateChart(Chart chart) {
    switch (chart.state) {
      case _stateAbsentNone:
        chart.icon = _absentIcon;
        chart.color = _absentColor;
        break;
      case _stateAbsentDownload:
        chart.icon = _downloadIcon;
        chart.color = _absentColor;
        break;
      case _stateCurrentNone:
        chart.icon = _downloadedIcon;
        chart.color = _currentColor;
        break;
      case _stateCurrentDownload:
        chart.icon = _downloadIcon;
        chart.color = _currentColor;
        break;
      case _stateCurrentDelete:
        chart.icon = _deleteIcon;
        chart.color = _currentColor;
        break;
      case _stateExpiredNone:
        chart.icon = _downloadedIcon;
        chart.color = _expiredColor;
        break;
      case _stateExpiredDownload:
        chart.icon = _downloadIcon;
        chart.color = _expiredColor;
        break;
      case _stateExpiredDelete:
        chart.icon = _deleteIcon;
        chart.color = _expiredColor;
        break;
    }
  }

  void _chartTouched(Chart chart) {
    switch (chart.state) {
      case _stateAbsentNone:
        chart.state = _stateAbsentDownload;
        break;
      case _stateAbsentDownload:
        chart.state = _stateAbsentNone;
        break;
      case _stateCurrentNone:
        chart.state = _stateCurrentDelete;
        break;
      case _stateCurrentDelete:
        chart.state = _stateCurrentDownload;
        break;
      case _stateCurrentDownload:
        chart.state = _stateCurrentNone;
        break;
      case _stateExpiredNone:
        chart.state = _stateExpiredDelete;
        break;
      case _stateExpiredDelete:
        chart.state = _stateExpiredDownload;
        break;
      case _stateExpiredDownload:
        chart.state = _stateExpiredNone;
        break;
    }
    setState(() {
      _updateChart(chart);
    });
  }

  static Future<bool> isAnyChartExpired() async {

    for(ChartCategory cg in _allCharts) {
      for(Chart chart in cg.charts) {
        if(await Download.isChartExpired(chart)) {
          return true;
        }
      }
    }
    return false;
  }

  static Future<bool> doesAnyChartExists() async {

    for(ChartCategory cg in _allCharts) {
      for(Chart chart in cg.charts) {
        bool exists = (await Download.getChartCycleLocal(chart)).isNotEmpty;
        if(exists) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _getChartStateFromLocal(Chart chart) async {
    String cycle = await Download.getChartCycleLocal(chart);
    bool expired = await Download.isChartExpired(chart);
    String range = FaaDates.getVersionRange(cycle);
    setState(() {
      if(cycle.isEmpty) {
        chart.state = _stateAbsentNone;
        chart.subtitle = "";
      }
      else if(expired) {
        chart.state = _stateExpiredNone;
        chart.subtitle = "$cycle $range";
      }
      else {
        chart.state = _stateCurrentNone;
        chart.subtitle = "$cycle $range";
      }
      _updateChart(chart);
      _updateCategory();
    });
  }

  void _updateCategory() {
    for (ChartCategory cg in _allCharts) {
      bool expired = false;
      bool current = false;
      bool downloading = false;
      for (Chart chart in cg.charts) {
        if (chart.progress.value > 0 && chart.progress.value < 100) {
          downloading = true;
        }
        switch (chart.state) {
          case _stateExpiredNone:
          case _stateExpiredDownload:
          case _stateExpiredDelete:
            expired = expired || true;
            break;
          case _stateCurrentNone:
          case _stateCurrentDownload:
          case _stateCurrentDelete:
            current = current || true;
          default:
            break;
        }
      }

      if (downloading) {
        cg.color = Colors.blue;
      }
      else if(expired) {
        cg.color = _expiredColor;
      }
      else if (current) {
        cg.color = _currentColor;
      }
      else {
        cg.color = _absentColor;
      }

    }
  }

  void _download() async {
    if(Storage().downloadManager.total() != 0) {
      Toast.showToast(context, "Please wait for ${Storage().downloadManager.total()} downloads to finish", null, 3);
      return;
    }
    for (int category = 0; category < _allCharts.length; category++) {
      for (int chart = 0; chart < _allCharts[category].charts.length; chart++) {
        ChartCategory cg = _allCharts[category];
        Chart ct = cg.charts[chart];
        if(!ct.enabled) {
          continue;
        }
        if(ct.name == "DatabasesX" && ct.state == _stateAbsentNone) {
          ct.state = _stateAbsentDownload;
        }
        if (ct.state == _stateAbsentDownload ||
            ct.state == _stateCurrentDownload) {
          Storage().downloadManager.download(ct, _nextCycle, _backupServer);
        }
        if (ct.state == _stateCurrentDelete ||
            ct.state == _stateExpiredDelete) {
          Storage().downloadManager.delete(ct);
        }
      }
    }
    if(0 == Storage().downloadManager.total()) {
      Toast.showToast(context, "Please select items to download", null, 3);
    }
    else {
      Toast.showToast(context, "Downloading ${Storage().downloadManager.total()} items", null, 3);
    }
  }

  void _update() async {
    if(Storage().downloadManager.total() != 0) {
      Toast.showToast(context, "Please wait for ${Storage().downloadManager.total()} downloads to finish", null, 3);
      return;
    }
    int updateCount = 0;
    for (int category = 0; category < _allCharts.length; category++) {
      for (int chart = 0; chart < _allCharts[category].charts.length; chart++) {
        ChartCategory cg = _allCharts[category];
        Chart ct = cg.charts[chart];
        if(!ct.enabled) {
          continue;
        }
        if (ct.state == _stateExpiredNone ||
            ct.state == _stateExpiredDownload ||
            ct.state == _stateExpiredDelete) {
          Storage().downloadManager.deleteSilent(ct);
          Storage().downloadManager.download(ct, _nextCycle, _backupServer);
          updateCount++;
        }
      }
    }
    if(updateCount == 0) {
      Toast.showToast(context, "All charts are up to date", null, 3);
    }
    else {
      Toast.showToast(context, "Updating $updateCount items", null, 3);
    }
  }

  static List<String> getCategories() {

    List<String> ret = [];

    for(ChartCategory cg in _allCharts) {
      if(cg.isChart) {
        ret.add(cg.title);
      }
    }

    return(ret);
  }

  static final List<ChartCategory> _allCharts = [
    ChartCategory(
      ChartCategory.databases,
      _absentColor,
      [
        Chart('DatabasesX', _absentColor, _absentIcon, 'databasesx', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Business/FBO', _absentColor, _absentIcon, 'databasesBusiness', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
      ],
      false,
    ),
    ChartCategory(
      ChartCategory.sectional,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('North Central', _absentColor, _absentIcon, 'NC_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('South Central', _absentColor, _absentIcon, 'SC_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_SEC', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
      ], true,
    ),
    ChartCategory(
      ChartCategory.tac,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('North Central', _absentColor, _absentIcon, 'NC_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('South Central', _absentColor, _absentIcon, 'SC_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_TAC', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
      ], true,
    ),
    ChartCategory(
      ChartCategory.ifrl,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('North Central', _absentColor, _absentIcon, 'NC_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('South Central', _absentColor, _absentIcon, 'SC_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_ENR_L', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
      ], true,
    ),
    ChartCategory(
      ChartCategory.ifrh,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('North Central', _absentColor, _absentIcon, 'NC_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('South Central', _absentColor, _absentIcon, 'SC_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_ENR_H', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
      ], true,
    ),
    ChartCategory(
      ChartCategory.ifra,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('North Central', _absentColor, _absentIcon, 'NC_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('South Central', _absentColor, _absentIcon, 'SC_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_ENR_A', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
      ], true,
    ),
    ChartCategory(
      ChartCategory.heli,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('North Central', _absentColor, _absentIcon, 'NC_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('South Central', _absentColor, _absentIcon, 'SC_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_HEL', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
      ], true,
    ),
    ChartCategory(
      ChartCategory.flyway,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('North Central', _absentColor, _absentIcon, 'NC_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('South Central', _absentColor, _absentIcon, 'SC_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_FLY', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
      ], true,
    ),

    ChartCategory(
      ChartCategory.plates,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('North Central', _absentColor, _absentIcon, 'NC_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('South Central', _absentColor, _absentIcon, 'SC_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_TPP', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
      ], false,
    ),
    ChartCategory(
      ChartCategory.csup,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('North Central', _absentColor, _absentIcon, 'NC_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('South Central', _absentColor, _absentIcon, 'SC_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_CSUP', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), true),
      ], false,
    ),
    ChartCategory(
      ChartCategory.elevation,
      _absentColor,
      [
        Chart('Northeast',     _absentColor, _absentIcon, 'NE_ELEVATION',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
        Chart('North Central', _absentColor, _absentIcon, 'NC_ELEVATION',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
        Chart('Northwest',     _absentColor, _absentIcon, 'NW_ELEVATION',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
        Chart('Southeast',     _absentColor, _absentIcon, 'SE_ELEVATION',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
        Chart('South Central', _absentColor, _absentIcon, 'SC_ELEVATION',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
        Chart('Southwest',     _absentColor, _absentIcon, 'SW_ELEVATION',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_ELEVATION',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_ELEVATION',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_ELEVATION', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download(), false),
      ], false,
    ),
  ];
}
