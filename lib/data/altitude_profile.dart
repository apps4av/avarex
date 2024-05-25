import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_charts/flutter_charts.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;


class AltitudeProfile {

  static Future<List<double>> getAltitudeProfile(List<LatLng> points) async {
    List<double> altitudes = [];
    String query = "https://api.open-elevation.com/api/v1/lookup";
    List<Map<String, double>> locations = [];
    for (int i = 0; i < points.length; i++) {
      locations.add({"latitude": points[i].latitude, "longitude": points[i].longitude});
    }
    var response = await http.post(Uri.parse(query), body: jsonEncode({"locations": locations}));
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      for (int i = 0; i < data['results'].length; i++) {
        altitudes.add(data['results'][i]['elevation'] * 3.28084);
      }
    }
    return altitudes;
  }

  static Widget makeChart(List<double> data) {
    if(data.isEmpty) {
      return Container();
    }
    LabelLayoutStrategy? xContainerLabelLayoutStrategy;
    ChartData chartData;
    // chart with no grid lines
    ChartOptions chartOptions = const ChartOptions();
    chartData = ChartData(dataRows: [data], xUserLabels: List.generate(data.length, (index) => index % 10 == 0 ? index.toString() : ""), dataRowsLegends: const ["Elevation ft/NM"], chartOptions: chartOptions);
    LineChartTopContainer lineChartContainer = LineChartTopContainer(
      chartData: chartData,
      xContainerLabelLayoutStrategy: xContainerLabelLayoutStrategy,
    );

    LineChart lineChart = LineChart(
      painter: LineChartPainter(
        lineChartContainer: lineChartContainer,
      ),
    );
    return lineChart;
  }


}


