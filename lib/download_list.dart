import 'package:avaremp/faa_dates.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'chart.dart';
import 'download.dart';


const int _stateAbsentNone = 0;
const int _stateAbsentDownload = 1;
const int _stateCurrentNone = 2;
const int _stateCurrentDownload = 3;
const int _stateCurrentDelete = 4;
const int _stateExpiredNone = 5;
const int _stateExpiredDownload = 6;
const int _stateExpiredDelete = 7;

const Color _absentColor = Colors.grey;
const Color _currentColor = Colors.green;
const Color _expiredColor = Colors.red;

const IconData _absentIcon = Icons.question_mark;
const IconData _downloadedIcon = Icons.check;
const IconData _downloadIcon = Icons.download;
const IconData _deleteIcon = Icons.delete;

class DownloadList extends StatefulWidget {
  const DownloadList({super.key});
  @override
  DownloadListState createState() => DownloadListState();
}

class DownloadListState extends State<DownloadList> {

  bool _stopped = false;

  DownloadListState() {
    for (ChartCategory cg in _allCharts) {
      for (Chart chart in cg.charts) {
        _getChartStateFromLocal(chart); // start with reading from disk async
      }
    }
  }

  @override
  void deactivate() {
    super.deactivate();
    // cancel all tasks
    _stopped = true;
  }

  @override
  void activate() {
    super.activate();
    // cancel all tasks
    _stopped = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: const Text("Download"),
        actions: [
          IconButton(icon: Icon(MdiIcons.refresh), padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), onPressed: () => {_start()},),
        ],
      ),

      body: ListView.builder(
        itemCount: _allCharts.length,
        itemBuilder: (context, index) {
          return ExpansionTile(
            title: Text(_allCharts[index].title, style: TextStyle(color: _allCharts[index].color)),
            children: <Widget>[
              Column(
                children: mBuildExpandableContent(index),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> mBuildExpandableContent(int index) {
    List<Widget> columnContent = [];
    ChartCategory chartCategory = _allCharts[index];

    for (Chart chart in chartCategory.charts) {
      columnContent.add(
        ListTile(
          title: Text(chart.name),
          subtitle: Text(chart.subtitle, style: TextStyle(color: chart.color),),
          trailing: CircularProgressIndicator(value: chart.progress),
          leading: Icon(chart.icon, color:chart.color),
          enabled: chart.enabled,
          // change icon on tap
          onTap: () {
            setState(() {
              _chartTouched(chart);
            });
          }
        ),
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

  void _downloadCallback(Chart chart, double progress) async {
    if(_stopped) { // view switched, cancel
      chart.enabled = true;
      chart.progress = 0;
      chart.download.cancel();
      return;
    }
    setState(() {
      chart.progress = progress;
      if(0 == progress) {
        chart.subtitle = "Downloading";
        chart.enabled = false;
      }
      else if(0.5 == progress) {
        chart.subtitle = "Installing";
        chart.enabled = false;
      }
      else if(1 == progress) {
        chart.progress = 0;
        chart.subtitle = "Download Success";
        chart.enabled = true;
      }
      else if(-1 == progress) {
        chart.progress = 0;
        chart.subtitle = "Download Failed";
        chart.enabled = true;
      }
    });
    if(-1 == progress || 1 == progress) {
      _getChartStateFromLocal(chart); // something changed
    }
  }

  void _deleteCallback(Chart chart, double progress) async {
    if(_stopped) {
      chart.enabled = true;
      chart.progress = 0;
      chart.download.cancel();
      return;
    }
    setState(() {
      chart.progress = progress;
      if(0 == progress) {
        chart.subtitle = "Uninstalling";
        chart.enabled = false;
      }
      else if(1 == progress) {
        chart.progress = 0;
        chart.enabled = true;
      }
      else if(-1 == progress) {
        chart.progress = 0;
        chart.enabled = true;
      }
    });
    if(-1 == progress || 1 == progress) {
      _getChartStateFromLocal(chart); // something changed
    }
  }

  // Do actions on all charts
  void _start() async {
    for (int category = 0; category < _allCharts.length; category++) {
      for (int chart = 0; chart < _allCharts[category].charts.length; chart++) {
        ChartCategory cg = _allCharts[category];
        Chart ct = cg.charts[chart];
        if(!ct.enabled) {
          continue;
        }
        // download expired or to-download item
        if (ct.state == _stateAbsentDownload ||
            ct.state == _stateCurrentDownload ||
            ct.state == _stateExpiredDownload) {
          // download this chart
          ct.download.download(ct, _downloadCallback);
        }
        if (ct.state == _stateCurrentDelete ||
            ct.state == _stateExpiredDelete) {
          // download this chart
          ct.download.delete(ct, _deleteCallback);
        }
      }
    }
  }

  // ALl that can be downloaded
  static final List<ChartCategory> _allCharts = [
    ChartCategory(
      ChartCategory.databases,
      _absentColor,
      [
        Chart('Databases', _absentColor, _absentIcon, 'databases', _stateAbsentNone, "", 0, true, Download()),
      ],
    ),
    ChartCategory(
      ChartCategory.sectional,
      _absentColor,
      [
        Chart('New York', _absentColor, _absentIcon, 'NewYork', _stateAbsentNone, "", 0, true, Download()),
        Chart('New York256', _absentColor, _absentIcon, 'NY', _stateAbsentNone, "", 0, true, Download()),
      ],
    ),
    ChartCategory(
      ChartCategory.tac,
      _absentColor,
      [
        Chart('Boston', _absentColor, _absentIcon, 'BostonTAC', _stateAbsentNone, "", 0, true, Download()),
      ],
    ),
    ChartCategory(
      ChartCategory.ifrl,
      _absentColor,
      [
        Chart('Northeast', _absentColor, _absentIcon, 'ELUS_NE', _stateAbsentNone, "", 0, true, Download()),
      ],
    ),
    ChartCategory(
      ChartCategory.plates,
      _absentColor,
      [
        Chart('MA', _absentColor, _absentIcon, 'MA_PLATES', _stateAbsentNone, "", 0, true, Download()),
      ],
    ),
    ChartCategory(
      ChartCategory.csup,
      _absentColor,
      [
        Chart('Northeast', _absentColor, _absentIcon, 'AFD_NE', _stateAbsentNone, "", 0, true, Download()),
      ],
    ),
  ];
}



