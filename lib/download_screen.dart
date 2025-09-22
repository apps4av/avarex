
import 'package:avaremp/faa_dates.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'chart.dart';
import 'constants.dart';
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

const IconData _absentIcon = Icons.question_mark;
const IconData _downloadedIcon = Icons.check;
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
        _getChartStateFromLocal(chart); // start with reading from disk async
      }
    }
    Storage().downloadManager.downloads.addListener(_finishedListener);
  }

  @override
  void dispose() {
    Storage().downloadManager.downloads.removeListener(_finishedListener);
    super.dispose();
  }

  // this is needed to sync when downloads are complete
  void _finishedListener() {
    for (ChartCategory cg in _allCharts) {
      for (Chart chart in cg.charts) {
        _getChartStateFromLocal(chart); // start with reading from disk async
      }
    }
  }

  // show regions file in a modal dialog using widgetzoom
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: Row(children:[const Text("Download"), IconButton(icon: const Icon(Icons.info), onPressed: _showMap )]),
        actions: [
          Padding(padding: const EdgeInsets.all(10), child: TextButton(onPressed: () => {_start()}, child: const Text("Start"))),
        ],
      ),

      body: Column(children:[
        Expanded(flex: 8, child: ListView.builder(
          itemCount: _allCharts.length,
          itemBuilder: (context, index) {
            return ExpansionTile(
              title: Text(_allCharts[index].title, style: TextStyle(color: _allCharts[index].color)),
              children: <Widget>[
                Column(
                  children: _buildExpandableContent(index),
                ),
              ],
            );
          },
        )),

        Expanded(flex: 1, child: Row(children:[

        Padding(padding: const EdgeInsets.all(10), child:TextButton(
            onPressed: () {
              setState(() {
                _nextCycle = !_nextCycle;
              });
            },
            child: _nextCycle ? const Text("Next Cycle") : const Text("This Cycle"))),
        Padding(padding: const EdgeInsets.all(10), child:TextButton(
            onPressed: () {
              setState(() {
                _backupServer = !_backupServer;
              });
            },
            child: _backupServer ? const Text("Backup Server") : const Text("Main Server")))])),
      ]),
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
              // download success
              chart.progress.value = 0;
              _getChartStateFromLocal(chart);
            }
            return ListTile(
              title: Text(chart.name),
              subtitle: Text(chart.subtitle, style: TextStyle(color: chart.color),),
              trailing: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(value: value.toDouble() / 100),
                Visibility(visible: value > 0, child:
                  IconButton(icon:  const Icon(Icons.stop_circle), onPressed: () { chart.download.cancel();},)),
              ]),
              leading: Icon(chart.icon, color:chart.color),
              enabled: chart.enabled,
              // change icon on tap
              onTap: () {
                setState(() {
                  _chartTouched(chart);
                });
              });
            })
        );
    }
    return columnContent;
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
        String current = FaaDates.getCurrentCycle();
        String cycle = await chart.download.getChartCycleLocal(chart);
        if(cycle.isEmpty) {
          continue;
        }
        if(cycle != current) {
          return true;
        }
      }
    }
    return false;
  }

  static Future<bool> doesAnyChartExists() async {

    for(ChartCategory cg in _allCharts) {
      for(Chart chart in cg.charts) {
        bool exists = (await chart.download.getChartCycleLocal(chart)).isNotEmpty;
        if(exists) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _getChartStateFromLocal(Chart chart) async {
    String cycle = await chart.download.getChartCycleLocal(chart);
    bool expired = await chart.download.isChartExpired(chart);
    String range = FaaDates.getVersionRange(cycle);
    setState(() {
      if(expired && cycle != "") {
        // available but expired
        chart.state = _stateExpiredNone;
        chart.subtitle = "$cycle $range";
      }
      else if(expired && cycle == "") {
        // missing
        chart.state = _stateAbsentNone;
        chart.subtitle = "";
      }
      else {
        // current
        chart.state = _stateCurrentNone;
        chart.subtitle = "$cycle $range";
      }
      _updateChart(chart);
      _updateCategory();
    });
  }

  // update color of category to reflect chart status
  void _updateCategory() {
    for (ChartCategory cg in _allCharts) {
      bool expired = false;
      bool current = false;
      for (Chart chart in cg.charts) {
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

      if(expired) {
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

  // Do actions on all charts
  void _start() async {
    if(Storage().downloadManager.total() != 0) {
      MapScreenState.showToast(context, "Please wait for ${Storage().downloadManager.total()} Downloads/Updates/Uninstalls to finish", null, 3);
      return; // let DL finish
    }
    for (int category = 0; category < _allCharts.length; category++) {
      for (int chart = 0; chart < _allCharts[category].charts.length; chart++) {
        ChartCategory cg = _allCharts[category];
        Chart ct = cg.charts[chart];
        if(!ct.enabled) {
          continue;
        }
        if(ct.name == "DatabasesX" && ct.state == _stateAbsentNone) {
          // if database is missing, download, there is no need to operate with db
          ct.state = _stateAbsentDownload;
        }
        // download expired or to-download item
        if (ct.state == _stateAbsentDownload ||
            ct.state == _stateCurrentDownload) {
          // download this chart
          Storage().downloadManager.download(ct, _nextCycle, _backupServer);
        }
        if (ct.state == _stateExpiredNone ||
            ct.state == _stateExpiredDownload) {
          Storage().downloadManager.deleteSilent(ct);
          Storage().downloadManager.download(ct, _nextCycle, _backupServer);
        }
        if (ct.state == _stateCurrentDelete ||
            ct.state == _stateExpiredDelete) {
          // delete this chart
          Storage().downloadManager.delete(ct);
        }
      }
    }
    if(0 == Storage().downloadManager.total()) {
      MapScreenState.showToast(context, "Please select items to Download/Update/Install", null, 3);
    }
    else {
      MapScreenState.showToast(context, "Downloading/Updating/Uninstalling ${Storage().downloadManager.total()} items", null, 3);
    }
  }

  // all chart categories that are downloadable
  static List<String> getCategories() {

    List<String> ret = [];

    for(ChartCategory cg in _allCharts) {
      if(cg.isChart) {
        ret.add(cg.title);
      }
    }

    return(ret);
  }

  // ALl that can be downloaded
  static final List<ChartCategory> _allCharts = [
    ChartCategory(
      ChartCategory.databases,
      _absentColor,
      [
        Chart('DatabasesX', _absentColor, _absentIcon, 'databasesx', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ],
      false,
    ),
    ChartCategory(
      ChartCategory.sectional,
      _absentColor,
      [
        Chart('Northeast',    _absentColor, _absentIcon, 'NE_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('North Central', _absentColor, _absentIcon, 'NC_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Northwest',    _absentColor, _absentIcon, 'NW_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southeast',    _absentColor, _absentIcon, 'SE_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('South Central', _absentColor, _absentIcon, 'SC_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southwest',    _absentColor, _absentIcon, 'SW_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_SEC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_SEC', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.tac,
      _absentColor,
      [
        Chart('Northeast',    _absentColor, _absentIcon, 'NE_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('North Central', _absentColor, _absentIcon, 'NC_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Northwest',    _absentColor, _absentIcon, 'NW_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southeast',    _absentColor, _absentIcon, 'SE_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('South Central', _absentColor, _absentIcon, 'SC_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southwest',    _absentColor, _absentIcon, 'SW_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_TAC',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_TAC', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.ifrl,
      _absentColor,
      [
        Chart('Northeast',    _absentColor, _absentIcon, 'NE_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('North Central', _absentColor, _absentIcon, 'NC_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Northwest',    _absentColor, _absentIcon, 'NW_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southeast',    _absentColor, _absentIcon, 'SE_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('South Central', _absentColor, _absentIcon, 'SC_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southwest',    _absentColor, _absentIcon, 'SW_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_ENR_L',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_ENR_L', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.ifrh,
      _absentColor,
      [
        Chart('Northeast',    _absentColor, _absentIcon, 'NE_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('North Central', _absentColor, _absentIcon, 'NC_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Northwest',    _absentColor, _absentIcon, 'NW_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southeast',    _absentColor, _absentIcon, 'SE_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('South Central', _absentColor, _absentIcon, 'SC_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southwest',    _absentColor, _absentIcon, 'SW_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_ENR_H',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_ENR_H', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.ifra,
      _absentColor,
      [
        Chart('Northeast',    _absentColor, _absentIcon, 'NE_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('North Central', _absentColor, _absentIcon, 'NC_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Northwest',    _absentColor, _absentIcon, 'NW_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southeast',    _absentColor, _absentIcon, 'SE_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('South Central', _absentColor, _absentIcon, 'SC_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southwest',    _absentColor, _absentIcon, 'SW_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_ENR_A',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_ENR_A', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.heli,
      _absentColor,
      [
        Chart('Northeast',    _absentColor, _absentIcon, 'NE_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('North Central', _absentColor, _absentIcon, 'NC_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Northwest',    _absentColor, _absentIcon, 'NW_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southeast',    _absentColor, _absentIcon, 'SE_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('South Central', _absentColor, _absentIcon, 'SC_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southwest',    _absentColor, _absentIcon, 'SW_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_HEL',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_HEL', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.flyway,
      _absentColor,
      [
        Chart('Northeast',    _absentColor, _absentIcon, 'NE_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('North Central', _absentColor, _absentIcon, 'NC_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Northwest',    _absentColor, _absentIcon, 'NW_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southeast',    _absentColor, _absentIcon, 'SE_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('South Central', _absentColor, _absentIcon, 'SC_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southwest',    _absentColor, _absentIcon, 'SW_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_FLY',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_FLY', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ], true,
    ),

    ChartCategory(
      ChartCategory.plates,
      _absentColor,
      [
        Chart('Northeast',    _absentColor, _absentIcon, 'NE_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('North Central', _absentColor, _absentIcon, 'NC_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Northwest',    _absentColor, _absentIcon, 'NW_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southeast',    _absentColor, _absentIcon, 'SE_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('South Central', _absentColor, _absentIcon, 'SC_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southwest',    _absentColor, _absentIcon, 'SW_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_TPP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_TPP', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ], false,
    ),
    ChartCategory(
      ChartCategory.csup,
      _absentColor,
      [
        Chart('Northeast',    _absentColor, _absentIcon, 'NE_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('North Central', _absentColor, _absentIcon, 'NC_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Northwest',    _absentColor, _absentIcon, 'NW_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southeast',    _absentColor, _absentIcon, 'SE_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('South Central', _absentColor, _absentIcon, 'SC_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Southwest',    _absentColor, _absentIcon, 'SW_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('East Central',  _absentColor, _absentIcon, 'EC_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Alaska',        _absentColor, _absentIcon, 'AK_CSUP',  _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
        Chart('Pacific',       _absentColor, _absentIcon, 'PAC_CSUP', _stateAbsentNone, "", ValueNotifier<int>(0), true, Download()),
      ], false,
    ),
  ];
}
