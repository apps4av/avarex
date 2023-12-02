import 'package:avaremp/faa_dates.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'chart.dart';
import 'download.dart';


const int stateAbsentNone = 0;
const int stateAbsentDownload = 1;
const int stateCurrentNone = 2;
const int stateCurrentDownload = 3;
const int stateCurrentDelete = 4;
const int stateExpiredNone = 5;
const int stateExpiredDownload = 6;
const int stateExpiredDelete = 7;

const Color absentColor = Colors.grey;
const Color currentColor = Colors.green;
const Color expiredColor = Colors.red;

const IconData absentIcon = Icons.question_mark;
const IconData downloadedIcon = Icons.check;
const IconData downloadIcon = Icons.download;
const IconData deleteIcon = Icons.delete;

class DownloadList extends StatefulWidget {
  const DownloadList({super.key});
  @override
  DownloadListState createState() => DownloadListState();
}

class DownloadListState extends State<DownloadList> {

  bool stopped = false;

  DownloadListState() {
    for (ChartCategory cg in allCharts) {
      for (Chart chart in cg.charts) {
        getChartStateFromLocal(chart); // start with reading from disk async
      }
    }
  }

  // ALl that can be downloaded
  static List<ChartCategory> allCharts = [
    ChartCategory(
      'Databases',
      absentColor,
      [
        Chart('Databases', absentColor, absentIcon, 'databases', stateAbsentNone, "", 0, true, Download()),
      ],
    ),
    ChartCategory(
      'VFR Sectional Charts',
      absentColor,
      [
        Chart('New York', absentColor, absentIcon, 'NewYork', stateAbsentNone, "", 0, true, Download()),
      ],
    ),
  ];

  @override
  void deactivate() {
    super.deactivate();
    // cancel all tasks
    stopped = true;
  }

  @override
  void activate() {
    super.activate();
    // cancel all tasks
    stopped = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: const Text("Download"),
        actions: [
          IconButton(icon: Icon(MdiIcons.refresh), padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), onPressed: () => {start()},),
        ],
      ),

      body: ListView.builder(
        itemCount: allCharts.length,
        itemBuilder: (context, index) {
          return ExpansionTile(
            title: Text(allCharts[index].title, style: TextStyle(color: allCharts[index].color)),
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
    ChartCategory chartCategory = allCharts[index];

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
              chartTouched(chart);
            });
          }
        ),
      );
    }

    return columnContent;
  }

  void updateChart(Chart chart) {
    switch (chart.state) {
      case stateAbsentNone:
        chart.icon = absentIcon;
        chart.color = absentColor;
        break;
      case stateAbsentDownload:
        chart.icon = downloadIcon;
        chart.color = absentColor;
        break;
      case stateCurrentNone:
        chart.icon = downloadedIcon;
        chart.color = currentColor;
        break;
      case stateCurrentDownload:
        chart.icon = downloadIcon;
        chart.color = currentColor;
        break;
      case stateCurrentDelete:
        chart.icon = deleteIcon;
        chart.color = currentColor;
        break;
      case stateExpiredNone:
        chart.icon = downloadedIcon;
        chart.color = expiredColor;
        break;
      case stateExpiredDownload:
        chart.icon = downloadIcon;
        chart.color = expiredColor;
        break;
      case stateExpiredDelete:
        chart.icon = deleteIcon;
        chart.color = expiredColor;
        break;
    }
  }

  void chartTouched(Chart chart) {
    switch (chart.state) {
      case stateAbsentNone:
        chart.state = stateAbsentDownload;
        break;
      case stateAbsentDownload:
        chart.state = stateAbsentNone;
        break;
      case stateCurrentNone:
        chart.state = stateCurrentDelete;
        break;
      case stateCurrentDelete:
        chart.state = stateCurrentDownload;
        break;
      case stateCurrentDownload:
        chart.state = stateCurrentNone;
        break;
      case stateExpiredNone:
        chart.state = stateExpiredDelete;
        break;
      case stateExpiredDelete:
        chart.state = stateExpiredDownload;
        break;
      case stateExpiredDownload:
        chart.state = stateExpiredNone;
        break;
    }
    setState(() {
      updateChart(chart);
    });
  }

  Future<void> getChartStateFromLocal(Chart chart) async {
    String cycle = await chart.download.getChartCycleLocal(chart);
    bool expired = await chart.download.isChartExpired(chart);
    String range = FaaDates.getVersionRange(cycle);
    setState(() {
      if(expired && cycle != "") {
        // available but expired
        chart.state = stateExpiredNone;
        chart.subtitle = "$cycle $range";
      }
      else if(expired && cycle == "") {
        // missing
        chart.state = stateAbsentNone;
        chart.subtitle = "";
      }
      else {
        // current
        chart.state = stateCurrentNone;
        chart.subtitle = "$cycle $range";
      }
      updateChart(chart);
      updateCategory();
    });
  }

  // update color of category to reflect chart status
  void updateCategory() {
    for (ChartCategory cg in allCharts) {
      bool expired = false;
      bool current = false;
      for (Chart chart in cg.charts) {
        switch (chart.state) {
          case stateExpiredNone:
          case stateExpiredDownload:
          case stateExpiredDelete:
            expired = expired || true;
            break;
          case stateCurrentNone:
          case stateCurrentDownload:
          case stateCurrentDelete:
            current = current || true;
          default:
            break;
        }
      }

      if(expired) {
        cg.color = expiredColor;
      }
      else if (current) {
        cg.color = currentColor;
      }
      else {
        cg.color = absentColor;
      }

    }
  }

  void downloadCallback(Chart chart, double progress) async {
    if(stopped) { // view switched, cancel
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
      getChartStateFromLocal(chart); // something changed
    }
  }

  void deleteCallback(Chart chart, double progress) async {
    if(stopped) {
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
      getChartStateFromLocal(chart); // something changed
    }
  }

  // Do actions on all charts
  void start() async {
    for (int category = 0; category < allCharts.length; category++) {
      for (int chart = 0; chart < allCharts[category].charts.length; chart++) {
        ChartCategory cg = allCharts[category];
        Chart ct = cg.charts[chart];
        if(!ct.enabled) {
          continue;
        }
        // download expired or to-download item
        if (ct.state == stateAbsentDownload ||
            ct.state == stateCurrentDownload ||
            ct.state == stateExpiredDownload) {
          // download this chart
          ct.download.download(ct, downloadCallback);
        }
        if (ct.state == stateCurrentDelete ||
            ct.state == stateExpiredDelete) {
          // download this chart
          ct.download.delete(ct, deleteCallback);
        }
      }
    }
  }

}



