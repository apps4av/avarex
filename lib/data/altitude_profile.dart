import 'dart:convert';

import 'package:avaremp/unit_conversion.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';


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
        altitudes.add(data['results'][i]['elevation'] * UnitConversion.mToF);
      }
    }
    return altitudes;
  }

  static LineChartBarData _line(List<FlSpot> points) {
    return LineChartBarData(
      spots: points,
      dotData: const FlDotData(
        show: false,
      ),
      isCurved: true,
      color: Colors.yellow,
      barWidth: 4,
    );
  }

  static Widget makeChart(List<double> data) {

    if(data.isEmpty) {
      return Container();
    }

    int len = data.length;
    List<FlSpot> points = [];
    double maxY = 1000;
    for(int p = 0; p < len; p++) {
      if(data[p] > maxY) {
        maxY = data[p];
      }
      points.add(FlSpot(p.toDouble(), data[p]));
    }

    return AspectRatio(
      aspectRatio: 1.5,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LineChart(
          LineChartData(
            minY: -300,
            maxY: maxY,
            minX: 0,
            maxX: len.toDouble(),
            lineTouchData: const LineTouchData(enabled: false),
            clipData: const FlClipData.all(),
            gridData: const FlGridData(
              show: true,
              drawVerticalLine: true,
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              _line(points),
            ],
            titlesData: const FlTitlesData(
              show: true,
            ),
          ),
        ),
      ),
    );

  }


}


