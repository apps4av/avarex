
import 'package:avaremp/faa_dates.dart';
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

  bool _stopped = false;
  int _total = 0;
  int _totalStartWith = 0;

  DownloadScreenState() {
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

  void _addToTotal() {
    setState(() {
      _total++;
      _totalStartWith++;
    });
  }

  void _initTotal() {
    setState(() {
      _totalStartWith = 0;
      _total = 0;
    });
  }

  void _removeFromTotal() {
    setState(() {
      _total--;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Download"),
        actions: [
          if(_total != 0)
            Text("${(_totalStartWith - _total)} / $_totalStartWith"),
          TextButton(onPressed: () => {_start()}, child: const Text("Start")),
        ],
      ),

      body: ListView.builder(
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
      ),
    );
  }

  List<Widget> _buildExpandableContent(int index) {
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

  void _downloadCallback(Chart chart, double progress) {
    if(_stopped) { // view switched, cancel
      chart.enabled = true;
      chart.progress = 0;
      chart.download.cancel();
      _removeFromTotal();
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
        // re-check all charts expiry
      }
      else if(-1 == progress) {
        chart.progress = 0;
        chart.subtitle = "Download Failed";
        chart.enabled = true;
      }
    });
    if(-1 == progress || 1 == progress) {
      _removeFromTotal();
      _getChartStateFromLocal(chart); // something changed
    }
  }

  void _deleteCallback(Chart chart, double progress) {
    if(_stopped) {
      chart.enabled = true;
      chart.progress = 0;
      chart.download.cancel();
      _removeFromTotal();
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
      _removeFromTotal();
      _getChartStateFromLocal(chart); // something changed
    }
  }

  // Do actions on all charts
  void _start() async {
    _initTotal();
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
            ct.state == _stateExpiredNone ||
            ct.state == _stateExpiredDownload) {
          // download this chart
          ct.download.download(ct, _downloadCallback);
          _addToTotal();
        }
        if (ct.state == _stateCurrentDelete ||
            ct.state == _stateExpiredDelete) {
          // delete this chart
          ct.download.delete(ct, _deleteCallback);
          _addToTotal();
        }
      }
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
        Chart('Databases', _absentColor, _absentIcon, 'databases', _stateAbsentNone, "", 0, true, Download()),
      ],
      false,
    ),
    ChartCategory(
      ChartCategory.sectional,
      _absentColor,
      [
        Chart('Albuquerque', _absentColor, _absentIcon, 'Albuquerque', _stateAbsentNone, "", 0, true, Download()),
        Chart('Anchorage', _absentColor, _absentIcon, 'Anchorage', _stateAbsentNone, "", 0, true, Download()),
        Chart('Atlanta', _absentColor, _absentIcon, 'Atlanta', _stateAbsentNone, "", 0, true, Download()),
        Chart('Bethel', _absentColor, _absentIcon, 'Bethel', _stateAbsentNone, "", 0, true, Download()),
        Chart('Billings', _absentColor, _absentIcon, 'Billings', _stateAbsentNone, "", 0, true, Download()),
        Chart('Brownsville', _absentColor, _absentIcon, 'Brownsville', _stateAbsentNone, "", 0, true, Download()),
        Chart('Cape Lisburne', _absentColor, _absentIcon, 'CapeLisburne', _stateAbsentNone, "", 0, true, Download()),
        Chart('Caribbean1', _absentColor, _absentIcon, 'Caribbean1', _stateAbsentNone, "", 0, true, Download()),
        Chart('Caribbean2', _absentColor, _absentIcon, 'Caribbean2', _stateAbsentNone, "", 0, true, Download()),
        Chart('Charlotte', _absentColor, _absentIcon, 'Charlotte', _stateAbsentNone, "", 0, true, Download()),
        Chart('Cheyenne', _absentColor, _absentIcon, 'Cheyenne', _stateAbsentNone, "", 0, true, Download()),
        Chart('Chicago', _absentColor, _absentIcon, 'Chicago', _stateAbsentNone, "", 0, true, Download()),
        Chart('Cincinnati', _absentColor, _absentIcon, 'Cincinnati', _stateAbsentNone, "", 0, true, Download()),
        Chart('Cold Bay', _absentColor, _absentIcon, 'ColdBay', _stateAbsentNone, "", 0, true, Download()),
        Chart('Dallas-Ft Worth', _absentColor, _absentIcon, 'Dallas-FtWorth', _stateAbsentNone, "", 0, true, Download()),
        Chart('Dawson', _absentColor, _absentIcon, 'Dawson', _stateAbsentNone, "", 0, true, Download()),
        Chart('Denver', _absentColor, _absentIcon, 'Denver', _stateAbsentNone, "", 0, true, Download()),
        Chart('Detroit', _absentColor, _absentIcon, 'Detroit', _stateAbsentNone, "", 0, true, Download()),
        Chart('Dutch Harbor', _absentColor, _absentIcon, 'DutchHarbor', _stateAbsentNone, "", 0, true, Download()),
        Chart('El Paso', _absentColor, _absentIcon, 'ElPaso', _stateAbsentNone, "", 0, true, Download()),
        Chart('Fairbanks', _absentColor, _absentIcon, 'Fairbanks', _stateAbsentNone, "", 0, true, Download()),
        Chart('Great Falls', _absentColor, _absentIcon, 'GreatFalls', _stateAbsentNone, "", 0, true, Download()),
        Chart('Green Bay', _absentColor, _absentIcon, 'GreenBay', _stateAbsentNone, "", 0, true, Download()),
        Chart('Halifax', _absentColor, _absentIcon, 'Halifax', _stateAbsentNone, "", 0, true, Download()),
        Chart('Hawaiian Islands', _absentColor, _absentIcon, 'HawaiianIslands', _stateAbsentNone, "", 0, true, Download()),
        Chart('Houston', _absentColor, _absentIcon, 'Houston', _stateAbsentNone, "", 0, true, Download()),
        Chart('Jacksonville', _absentColor, _absentIcon, 'Jacksonville', _stateAbsentNone, "", 0, true, Download()),
        Chart('Juneau', _absentColor, _absentIcon, 'Juneau', _stateAbsentNone, "", 0, true, Download()),
        Chart('Kansas City', _absentColor, _absentIcon, 'KansasCity', _stateAbsentNone, "", 0, true, Download()),
        Chart('Ketchikan', _absentColor, _absentIcon, 'Ketchikan', _stateAbsentNone, "", 0, true, Download()),
        Chart('Klamath Falls', _absentColor, _absentIcon, 'KlamathFalls', _stateAbsentNone, "", 0, true, Download()),
        Chart('Kodiak', _absentColor, _absentIcon, 'Kodiak', _stateAbsentNone, "", 0, true, Download()),
        Chart('Lake Huron', _absentColor, _absentIcon, 'LakeHuron', _stateAbsentNone, "", 0, true, Download()),
        Chart('Las Vegas', _absentColor, _absentIcon, 'LasVegas', _stateAbsentNone, "", 0, true, Download()),
        Chart('Los Angeles', _absentColor, _absentIcon, 'LosAngeles', _stateAbsentNone, "", 0, true, Download()),
        Chart('McGrath', _absentColor, _absentIcon, 'McGrath', _stateAbsentNone, "", 0, true, Download()),
        Chart('Memphis', _absentColor, _absentIcon, 'Memphis', _stateAbsentNone, "", 0, true, Download()),
        Chart('Miami', _absentColor, _absentIcon, 'Miami', _stateAbsentNone, "", 0, true, Download()),
        Chart('Montreal', _absentColor, _absentIcon, 'Montreal', _stateAbsentNone, "", 0, true, Download()),
        Chart('New Orleans', _absentColor, _absentIcon, 'NewOrleans', _stateAbsentNone, "", 0, true, Download()),
        Chart('New York', _absentColor, _absentIcon, 'NewYork', _stateAbsentNone, "", 0, true, Download()),
        Chart('Nome', _absentColor, _absentIcon, 'Nome', _stateAbsentNone, "", 0, true, Download()),
        Chart('Omaha', _absentColor, _absentIcon, 'Omaha', _stateAbsentNone, "", 0, true, Download()),
        Chart('Phoenix', _absentColor, _absentIcon, 'Phoenix', _stateAbsentNone, "", 0, true, Download()),
        Chart('Point Barrow', _absentColor, _absentIcon, 'PointBarrow', _stateAbsentNone, "", 0, true, Download()),
        Chart('Salt Lake City', _absentColor, _absentIcon, 'SaltLakeCity', _stateAbsentNone, "", 0, true, Download()),
        Chart('San Antonio', _absentColor, _absentIcon, 'SanAntonio', _stateAbsentNone, "", 0, true, Download()),
        Chart('San Francisco', _absentColor, _absentIcon, 'SanFrancisco', _stateAbsentNone, "", 0, true, Download()),
        Chart('Seattle', _absentColor, _absentIcon, 'Seattle', _stateAbsentNone, "", 0, true, Download()),
        Chart('Seward', _absentColor, _absentIcon, 'Seward', _stateAbsentNone, "", 0, true, Download()),
        Chart('St. Louis', _absentColor, _absentIcon, 'StLouis', _stateAbsentNone, "", 0, true, Download()),
        Chart('Twin Cities', _absentColor, _absentIcon, 'TwinCities', _stateAbsentNone, "", 0, true, Download()),
        Chart('Washington', _absentColor, _absentIcon, 'Washington', _stateAbsentNone, "", 0, true, Download()),
        Chart('Wichita', _absentColor, _absentIcon, 'Wichita', _stateAbsentNone, "", 0, true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.tac,
      _absentColor,
      [
        Chart('Anchorage', _absentColor, _absentIcon, 'AnchorageTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Atlanta', _absentColor, _absentIcon, 'AtlantaTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Baltimore-Washington', _absentColor, _absentIcon, 'Baltimore-WashingtonTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Boston', _absentColor, _absentIcon, 'BostonTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Charlotte', _absentColor, _absentIcon, 'CharlotteTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Chicago', _absentColor, _absentIcon, 'ChicagoTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Cincinnati', _absentColor, _absentIcon, 'CincinnatiTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Cleveland', _absentColor, _absentIcon, 'ClevelandTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Colorado Springs', _absentColor, _absentIcon, 'ColoradoSpringsTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Dallas-FtWorth', _absentColor, _absentIcon, 'Dallas-FtWorthTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Denver', _absentColor, _absentIcon, 'DenverTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Detroit', _absentColor, _absentIcon, 'DetroitTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Fairbanks', _absentColor, _absentIcon, 'FairbanksTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Honolulu Inset', _absentColor, _absentIcon, 'HonoluluInset', _stateAbsentNone, "", 0, true, Download()),
        Chart('Houston', _absentColor, _absentIcon, 'HoustonTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Kansas City', _absentColor, _absentIcon, 'KansasCityTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Las Vegas', _absentColor, _absentIcon, 'LasVegasTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Los Angeles', _absentColor, _absentIcon, 'LosAngelesTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Memphis', _absentColor, _absentIcon, 'MemphisTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Miami', _absentColor, _absentIcon, 'MiamiTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Minneapolis-StPaul', _absentColor, _absentIcon, 'Minneapolis-StPaulTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('New Orleans', _absentColor, _absentIcon, 'NewOrleansTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('New York', _absentColor, _absentIcon, 'NewYorkTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Orlando', _absentColor, _absentIcon, 'OrlandoTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Philadelphia', _absentColor, _absentIcon, 'PhiladelphiaTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Phoenix', _absentColor, _absentIcon, 'PhoenixTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Pittsburgh', _absentColor, _absentIcon, 'PittsburghTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Portland', _absentColor, _absentIcon, 'PortlandTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('PuertoRico-VI', _absentColor, _absentIcon, 'PuertoRico-VITAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Salt Lake City', _absentColor, _absentIcon, 'SaltLakeCityTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('San Diego', _absentColor, _absentIcon, 'SanDiegoTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('San Francisco', _absentColor, _absentIcon, 'SanFranciscoTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Seattle', _absentColor, _absentIcon, 'SeattleTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('St Louis', _absentColor, _absentIcon, 'StLouisTAC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Tampa', _absentColor, _absentIcon, 'TampaTAC', _stateAbsentNone, "", 0, true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.ifrl,
      _absentColor,
      [
        Chart('NE', _absentColor, _absentIcon, 'ELUS_NE', _stateAbsentNone, "", 0, true, Download()),
        Chart('NC', _absentColor, _absentIcon, 'ELUS_NC', _stateAbsentNone, "", 0, true, Download()),
        Chart('NW', _absentColor, _absentIcon, 'ELUS_NW', _stateAbsentNone, "", 0, true, Download()),
        Chart('SE', _absentColor, _absentIcon, 'ELUS_SE', _stateAbsentNone, "", 0, true, Download()),
        Chart('SC', _absentColor, _absentIcon, 'ELUS_SC', _stateAbsentNone, "", 0, true, Download()),
        Chart('SW', _absentColor, _absentIcon, 'ELIS_SW', _stateAbsentNone, "", 0, true, Download()),
        Chart('AK', _absentColor, _absentIcon, 'ELUS_AK', _stateAbsentNone, "", 0, true, Download()),
        Chart('HI', _absentColor, _absentIcon, 'ELUS_HI', _stateAbsentNone, "", 0, true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.ifrh,
      _absentColor,
      [
        Chart('NE', _absentColor, _absentIcon, 'EHUS_NE', _stateAbsentNone, "", 0, true, Download()),
        Chart('NC', _absentColor, _absentIcon, 'EHUS_NC', _stateAbsentNone, "", 0, true, Download()),
        Chart('NW', _absentColor, _absentIcon, 'EHUS_NW', _stateAbsentNone, "", 0, true, Download()),
        Chart('SE', _absentColor, _absentIcon, 'EHUS_SE', _stateAbsentNone, "", 0, true, Download()),
        Chart('SC', _absentColor, _absentIcon, 'EHUS_SC', _stateAbsentNone, "", 0, true, Download()),
        Chart('SW', _absentColor, _absentIcon, 'EHIS_SW', _stateAbsentNone, "", 0, true, Download()),
        Chart('AK', _absentColor, _absentIcon, 'EHUS_AK', _stateAbsentNone, "", 0, true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.ifra,
      _absentColor,
      [
        Chart('Anchorage', _absentColor, _absentIcon, 'ENRA_ANC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Atlanta', _absentColor, _absentIcon, 'ENRA_ATL', _stateAbsentNone, "", 0, true, Download()),
        Chart('Washington DC', _absentColor, _absentIcon, 'ENRA_DCA', _stateAbsentNone, "", 0, true, Download()),
        Chart('Denver', _absentColor, _absentIcon, 'ENRA_DEN', _stateAbsentNone, "", 0, true, Download()),
        Chart('Detroit', _absentColor, _absentIcon, 'ENRA_DET', _stateAbsentNone, "", 0, true, Download()),
        Chart('Dallas-FtWorth', _absentColor, _absentIcon, 'ENRA_DFW', _stateAbsentNone, "", 0, true, Download()),
        Chart('Fairbanks', _absentColor, _absentIcon, 'ENRA_FAI', _stateAbsentNone, "", 0, true, Download()),
        Chart('Guam', _absentColor, _absentIcon, 'ENRA_GUA', _stateAbsentNone, "", 0, true, Download()),
        Chart('Jacksonville', _absentColor, _absentIcon, 'ENRA_JAX', _stateAbsentNone, "", 0, true, Download()),
        Chart('Juneau', _absentColor, _absentIcon, 'ENRA_JNU', _stateAbsentNone, "", 0, true, Download()),
        Chart('Los Angeles', _absentColor, _absentIcon, 'ENRA_LAX', _stateAbsentNone, "", 0, true, Download()),
        Chart('Miami', _absentColor, _absentIcon, 'ENRA_MIA', _stateAbsentNone, "", 0, true, Download()),
        Chart('Kansas City Municipal', _absentColor, _absentIcon, 'ENRA_MKC', _stateAbsentNone, "", 0, true, Download()),
        Chart('Minneapolis', _absentColor, _absentIcon, 'ENRA_MSP', _stateAbsentNone, "", 0, true, Download()),
        Chart('Nome', _absentColor, _absentIcon, 'ENRA_OME', _stateAbsentNone, "", 0, true, Download()),
        Chart('OHare', _absentColor, _absentIcon, 'ENRA_ORD', _stateAbsentNone, "", 0, true, Download()),
        Chart('Phoenix', _absentColor, _absentIcon, 'ENRA_PHX', _stateAbsentNone, "", 0, true, Download()),
        Chart('San Fransisco', _absentColor, _absentIcon, 'ENRA_SFO', _stateAbsentNone, "", 0, true, Download()),
        Chart('Seattle', _absentColor, _absentIcon, 'ENRA_STL', _stateAbsentNone, "", 0, true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.heli,
      _absentColor,
      [
        Chart('Grand Canyon', _absentColor, _absentIcon, 'GrandCanyon', _stateAbsentNone, "", 0, true, Download()),
        Chart('Baltimore Heli', _absentColor, _absentIcon, 'BaltimoreHeli', _stateAbsentNone, "", 0, true, Download()),
        Chart('Boston Heli', _absentColor, _absentIcon, 'BostonHeli', _stateAbsentNone, "", 0, true, Download()),
        Chart('Chicago Heli', _absentColor, _absentIcon, 'ChicagoHeli', _stateAbsentNone, "", 0, true, Download()),
        Chart('Dallas-FtWorth', _absentColor, _absentIcon, 'Dallas-FtWorthHeli', _stateAbsentNone, "", 0, true, Download()),
        Chart('Detroit', _absentColor, _absentIcon, 'DetroitHeli', _stateAbsentNone, "", 0, true, Download()),
        Chart('Houston', _absentColor, _absentIcon, 'HoustonHeli', _stateAbsentNone, "", 0, true, Download()),
        Chart('Los Angeles', _absentColor, _absentIcon, 'LosAngelesHeli', _stateAbsentNone, "", 0, true, Download()),
        Chart('New York', _absentColor, _absentIcon, 'NewYorkHeli', _stateAbsentNone, "", 0, true, Download()),
        Chart('US Gulf Coast', _absentColor, _absentIcon, 'USGulfCoastHeli', _stateAbsentNone, "", 0, true, Download()),
        Chart('Washington', _absentColor, _absentIcon, 'WashingtonHeli', _stateAbsentNone, "", 0, true, Download()),
      ], true,
    ),
    ChartCategory(
      ChartCategory.flyway,
      _absentColor,
      [
        Chart('Atlanta', _absentColor, _absentIcon, 'AtlantaFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Baltimore-Washington', _absentColor, _absentIcon, 'Baltimore-WashingtonFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Charlotte', _absentColor, _absentIcon, 'CharlotteFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Chicago', _absentColor, _absentIcon, 'ChicagoFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Cincinnati', _absentColor, _absentIcon, 'CincinnatiFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Dallas-FtWorth', _absentColor, _absentIcon, 'Dallas-FtWorthFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Denver', _absentColor, _absentIcon, 'DenverFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Detroit', _absentColor, _absentIcon, 'DetroitFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Houston', _absentColor, _absentIcon, 'HoustonFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Las Vegas', _absentColor, _absentIcon, 'LasVegasFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Los Angeles', _absentColor, _absentIcon, 'LosAngelesFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Miami', _absentColor, _absentIcon, 'MiamiFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('New Orleans', _absentColor, _absentIcon, 'NewOrleansFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Orlando', _absentColor, _absentIcon, 'OrlandoFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Salt Lake City', _absentColor, _absentIcon, 'SaltLakeCityFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('San Diego', _absentColor, _absentIcon, 'SanDiegoFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('San Francisco', _absentColor, _absentIcon, 'SanFranciscoFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Seattle', _absentColor, _absentIcon, 'SeattleFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('St Louis', _absentColor, _absentIcon, 'StLouisFLY', _stateAbsentNone, "", 0, true, Download()),
        Chart('Tampa', _absentColor, _absentIcon, 'TampaFLY', _stateAbsentNone, "", 0, true, Download()),
      ], true,
    ),

    ChartCategory(
      ChartCategory.plates,
      _absentColor,
      [
        Chart('Takeoff/Alternate Minimums', _absentColor, _absentIcon, 'alternates', _stateAbsentNone, "", 0, true, Download()),
        Chart('AK', _absentColor, _absentIcon, 'AK_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('AZ', _absentColor, _absentIcon, 'AZ_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('AR', _absentColor, _absentIcon, 'AR_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('CA', _absentColor, _absentIcon, 'CA_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('CO', _absentColor, _absentIcon, 'CO_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('CT', _absentColor, _absentIcon, 'CT_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('DC', _absentColor, _absentIcon, 'DC_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('DE', _absentColor, _absentIcon, 'DE_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('FL', _absentColor, _absentIcon, 'FL_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('GA', _absentColor, _absentIcon, 'GA_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('HI', _absentColor, _absentIcon, 'HI_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('ID', _absentColor, _absentIcon, 'ID_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('IL', _absentColor, _absentIcon, 'IL_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('IN', _absentColor, _absentIcon, 'IN_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('IA', _absentColor, _absentIcon, 'IA_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('KS', _absentColor, _absentIcon, 'KS_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('KY', _absentColor, _absentIcon, 'KY_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('LA', _absentColor, _absentIcon, 'LA_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('ME', _absentColor, _absentIcon, 'ME_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('MD', _absentColor, _absentIcon, 'MD_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('MA', _absentColor, _absentIcon, 'MA_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('MI', _absentColor, _absentIcon, 'MI_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('MN', _absentColor, _absentIcon, 'MN_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('MS', _absentColor, _absentIcon, 'MS_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('MO', _absentColor, _absentIcon, 'MO_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('MT', _absentColor, _absentIcon, 'MT_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('NE', _absentColor, _absentIcon, 'NE_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('NV', _absentColor, _absentIcon, 'NV_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('NH', _absentColor, _absentIcon, 'NH_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('NJ', _absentColor, _absentIcon, 'NJ_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('NM', _absentColor, _absentIcon, 'NM_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('NY', _absentColor, _absentIcon, 'NY_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('NC', _absentColor, _absentIcon, 'NC_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('ND', _absentColor, _absentIcon, 'ND_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('OH', _absentColor, _absentIcon, 'OH_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('OK', _absentColor, _absentIcon, 'OK_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('OR', _absentColor, _absentIcon, 'OR_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('PA', _absentColor, _absentIcon, 'PA_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('PR', _absentColor, _absentIcon, 'PR_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('RI', _absentColor, _absentIcon, 'RI_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('SC', _absentColor, _absentIcon, 'SC_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('SD', _absentColor, _absentIcon, 'SD_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('TN', _absentColor, _absentIcon, 'TN_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('TX', _absentColor, _absentIcon, 'TX_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('UT', _absentColor, _absentIcon, 'UT_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('VT', _absentColor, _absentIcon, 'VT_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('VA', _absentColor, _absentIcon, 'VA_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('VI', _absentColor, _absentIcon, 'VI_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('WA', _absentColor, _absentIcon, 'WA_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('WV', _absentColor, _absentIcon, 'WV_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('WI', _absentColor, _absentIcon, 'WI_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('WY', _absentColor, _absentIcon, 'WY_PLATES', _stateAbsentNone, "", 0, true, Download()),
        Chart('XX', _absentColor, _absentIcon, 'XX_PLATES', _stateAbsentNone, "", 0, true, Download()),
      ], false,
    ),
    ChartCategory(
      ChartCategory.csup,
      _absentColor,
      [
        Chart('NE', _absentColor, _absentIcon, 'AFD_NE', _stateAbsentNone, "", 0, true, Download()),
        Chart('NC', _absentColor, _absentIcon, 'AFD_NC', _stateAbsentNone, "", 0, true, Download()),
        Chart('NW', _absentColor, _absentIcon, 'AFD_NW', _stateAbsentNone, "", 0, true, Download()),
        Chart('SE', _absentColor, _absentIcon, 'AFD_SE', _stateAbsentNone, "", 0, true, Download()),
        Chart('SC', _absentColor, _absentIcon, 'AFD_SC', _stateAbsentNone, "", 0, true, Download()),
        Chart('SW', _absentColor, _absentIcon, 'AFD_SW', _stateAbsentNone, "", 0, true, Download()),
        Chart('EC', _absentColor, _absentIcon, 'AFD_EC', _stateAbsentNone, "", 0, true, Download()),
        Chart('AK', _absentColor, _absentIcon, 'AFD_AK', _stateAbsentNone, "", 0, true, Download()),
        Chart('PAC', _absentColor, _absentIcon, 'AFD_PAC', _stateAbsentNone, "", 0, true, Download()),
      ], false,
    ),
  ];
}
