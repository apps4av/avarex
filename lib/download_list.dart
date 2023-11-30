import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

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

  // ALl that can be downloaded
  static List<ChartCategory> allCharts = [
    ChartCategory(
      'Databases',
      absentColor,
      [
        Chart('Databases', absentColor, absentIcon, 'databases', stateAbsentNone, "", 0),
      ],
    ),
    ChartCategory(
      'VFR Sectional Charts',
      absentColor,
      [
        Chart('New York', absentColor, absentIcon, 'NewYork', stateAbsentNone, "", 0),
      ],
    ),
  ];

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
            title: Text(allCharts[index].title),
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
        chart.subtitle = "";
        chart.color = absentColor;
        break;
      case stateAbsentDownload:
        chart.icon = downloadIcon;
        chart.subtitle = "";
        chart.color = absentColor;
        break;
      case stateCurrentNone:
        chart.icon = downloadedIcon;
        chart.subtitle = "Current";
        chart.color = currentColor;
        break;
      case stateCurrentDownload:
        chart.icon = downloadIcon;
        chart.subtitle = "Current";
        chart.color = currentColor;
        break;
      case stateCurrentDelete:
        chart.icon = deleteIcon;
        chart.subtitle = "Current";
        chart.color = currentColor;
        break;
      case stateExpiredNone:
        chart.icon = downloadedIcon;
        chart.subtitle = "Expired";
        chart.color = expiredColor;
        break;
      case stateExpiredDownload:
        chart.icon = downloadIcon;
        chart.subtitle = "Expired";
        chart.color = expiredColor;
        break;
      case stateExpiredDelete:
        chart.icon = deleteIcon;
        chart.subtitle = "Expired";
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
        chart.state = stateCurrentDownload;
        break;
      case stateCurrentDownload:
        chart.state = stateCurrentDelete;
        break;
      case stateCurrentDelete:
        chart.state = stateCurrentNone;
        break;
      case stateExpiredNone:
        chart.state = stateExpiredDownload;
        break;
      case stateExpiredDownload:
        chart.state = stateExpiredDelete;
        break;
      case stateExpiredDelete:
        chart.state = stateExpiredNone;
        break;
    }
    updateChart(chart);
  }

  void dlCallback(Chart chart, double progress) async {
    setState(() {
      chart.progress = progress;
      if(progress.round() == 1) {
        chart.progress = 0;
      }
      if(-1 == progress.round()) {
        chart.progress = 0;
        chart.subtitle = "Download Failed";
      }
    });
  }

  // Do actions on all charts
  void start() async {
    for (int category = 0; category < allCharts.length; category++) {
      for (int chart = 0; chart < allCharts[category].charts.length; chart++) {
        ChartCategory cg = allCharts[category];
        Chart ct = cg.charts[chart];
        // download expired or to-download item
        if(ct.state == stateAbsentDownload || ct.state == stateCurrentDownload || ct.state == stateExpiredDownload) {
          // download this chart
          Download d = Download();
          d.download(ct, dlCallback);
        }
        if(ct.state == stateCurrentDelete || ct.state == stateExpiredDelete) {
          // download this chart
          Download d = Download();
          d.delete(ct, dlCallback);
        }
      }
    }
  }

  void refreshAllCharts(String filename) {
    for (ChartCategory cg in allCharts) {
      for (Chart chart in cg.charts) {
        updateChart(chart);
      }
    }
  }
}



// Each chart in a list, color gray mean not downloaded, green means downloaded and current, red means downloaded and expired
class Chart {
  String name;
  String filename;
  IconData icon;
  int state;
  double progress; // 0 to 1 = 100%
  String subtitle;
  Color color;
  Chart(this.name, this.color, this.icon, this.filename, this.state, this.subtitle, this.progress);
}

// Chart category like sectional, IFR, ...
class ChartCategory {
  String title;
  Color color;
  List<Chart> charts;
  ChartCategory(this.title, this.color, this.charts);
}



