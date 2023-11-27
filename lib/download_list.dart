import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'download.dart';

class DownloadList extends StatefulWidget {
  const DownloadList({super.key});
  @override
  DownloadListState createState() => DownloadListState();
}

class DownloadListState extends State<DownloadList> {

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
        itemCount: mAllCharts.length,
        itemBuilder: (context, index) {
          return ExpansionTile(
            title: Text(mAllCharts[index].title),
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
    ChartCategory chartCategory = mAllCharts[index];

    for (Chart chart in chartCategory.charts) {
      columnContent.add(
        ListTile(
          title: Text(chart.name),
          subtitle: Text(chart.state),
          leading: Icon(chart.icon),
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

  void chartTouched(Chart chart) {
    if(chart.state == mChartStateNotDownloaded) {
      if(chart.icon == mDownloadIcon) {
        chart.icon = mNotDownloadedIcon;
      }
      else {
        chart.icon = mDownloadIcon;
      }
    }
    else {
      if(chart.icon == mDownloadedIcon) {
        chart.icon = mDeleteIcon;
      }
      else {
        chart.icon = mDownloadedIcon;
      }
    }

  }

  // Do actions on all charts
  void start() async {
    for (int category = 0; category < mAllCharts.length; category++) {
      for (int chart = 0; chart < mAllCharts[category].charts.length; chart++) {
        ChartCategory cg = mAllCharts[category];
        Chart ct = cg.charts[chart];
        // download expired or to-download item
        if(ct.icon == mDownloadIcon) {
          // download this chart
          Download d = Download();
          d.downloadFile(ct.filename);
        }
        if(ct.icon == mDeleteIcon) {
          // delete this chart
        }
      }
    }
  }

}

// Each chart in a list, color gray mean not downloaded, green means downloaded and current, red means downloaded and expired
class Chart {
  String name;
  Color color;
  IconData icon;
  String filename;
  String state;
  Chart(this.name, this.color, this.icon, this.filename, this.state);
}

// Chart category like sectional, IFR, ...
class ChartCategory {
  String title;
  Color color;
  List<Chart> charts;
  ChartCategory(this.title, this.color, this.charts);
}

const String mChartStateNotDownloaded = "Not Downloaded";
const IconData mNotDownloadedIcon = Icons.question_mark;
const IconData mDownloadedIcon = Icons.check;
const IconData mDownloadIcon = Icons.download;
const IconData mDeleteIcon = Icons.delete;

const Color mMissingColor = Colors.grey;
const Color mCurrentColor = Colors.green;
const Color mExpiredColor = Colors.red;

// ALl that can be downloaded
List<ChartCategory> mAllCharts = [
  ChartCategory(
    'Databases',
    mMissingColor,
    [
      Chart('Databases', mMissingColor, mNotDownloadedIcon, 'databases', mChartStateNotDownloaded),
    ],
  ),
  ChartCategory(
    'VFR Sectional Charts',
    mMissingColor,
    [
      Chart('New York', mMissingColor, mNotDownloadedIcon, 'NewYorkSectional', mChartStateNotDownloaded),
    ],
  ),
];
