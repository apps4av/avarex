import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class Saa {
  final String designator;
  final String name;
  final String frequencyTx;
  final String frequencyRx;
  final String upperLimit;
  final String lowerLimit;
  final String beginTime;
  final String endTime;
  final String beginDay;
  final String endDay;
  final String day;
  final LatLng coordinate;

  Saa({
    required this.designator,
    required this.name,
    required this.frequencyTx,
    required this.frequencyRx,
    required this.coordinate,
    required this.upperLimit,
    required this.lowerLimit,
    required this.beginTime,
    required this.endTime,
    required this.beginDay,
    required this.endDay,
    required this.day});

  factory Saa.fromMap(Map<String, dynamic> maps) {
    return Saa(
      designator : maps['designator'] as String,
      name : maps['name'] as String,
      frequencyTx: maps['FreqTx'] as String,
      frequencyRx: maps['FreqRx'] as String,
      day: maps['day'] as String,
      upperLimit: maps['upperlimit'] as String,
      lowerLimit: maps['lowerlimit'] as String,
      beginTime: maps['begintime'] as String,
      endTime: maps['endtime'] as String,
      beginDay: maps['beginday'] as String,
      endDay: maps['endday'] as String,
      coordinate: LatLng(maps['lat'] as double, maps['lon'] as double));
  }

  Widget toWidget() {
    int cut = day.toLowerCase().indexOf("altitudes. ");
    String abbreviated = day;
    if(cut > 0) {
      abbreviated = day.substring(cut + "altitudes. ".length);
    }
    // create a table widget
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(2)
      },
      children: [
        TableRow(
          children: [
            const Text("Designator", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(designator, style: const TextStyle(fontWeight: FontWeight.bold))
          ]
        ),
        TableRow(
          children: [
            const Text("Name"),
            Text(name)
          ]
        ),
        TableRow(
          children: [
            const Text("Freq. TX"),
            Text(frequencyTx)
          ]
        ),
        TableRow(
          children: [
            const Text("Freq. RX"),
            Text(frequencyRx)
          ]
        ),
        TableRow(
          children: [
            const Text("Top"),
            Text(upperLimit)
          ]
        ),
        TableRow(
          children: [
            const Text("Bottom"),
            Text(lowerLimit)
          ]
        ),
        TableRow(
          children: [
            const Text("Begin Hour"),
            Text(beginTime)
          ]
        ),
        TableRow(
          children: [
            const Text("End Hour"),
            Text(endTime)
          ]
        ),
        TableRow(
          children: [
            const Text("Begin Day"),
            Text(beginDay)
          ]
        ),
        TableRow(
          children: [
            const Text("End Day"),
            Text(endDay)
          ]
        ),
        TableRow(
          children: [
            const Text("Description"),
            Text(abbreviated)
          ]
        )
      ]
    );

  }
}