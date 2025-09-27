import 'dart:math';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'log_entry.dart';

class FilterableLogbookDashboard extends StatefulWidget {
  final List<LogEntry> logEntries;

  FilterableLogbookDashboard({required this.logEntries});

  @override
  _FilterableLogbookDashboardState createState() =>
      _FilterableLogbookDashboardState();
}

class _FilterableLogbookDashboardState
    extends State<FilterableLogbookDashboard> {
  Set<String> selectedYears = {};
  Set<String> selectedMakeModels = {};
  Set<String> selectedTails = {};
  Set<String> selectedRemarks = {};

  List<LogEntry> get filteredEntries {
    return widget.logEntries.where((e) {
      final yearMatch =
          selectedYears.isEmpty || selectedYears.contains(e.date.year.toString());
      final makeModelMatch = selectedMakeModels.isEmpty ||
          selectedMakeModels.contains(e.aircraftMakeModel);
      final tailMatch = selectedTails.isEmpty || selectedTails.contains(e.aircraftIdentification);
      final remarkMatch = selectedRemarks.isEmpty || selectedRemarks.any((remark) => e.remarks.contains(remark));
      return yearMatch && makeModelMatch && tailMatch && remarkMatch;
    }).toList();
  }

  Map<String, double> _aggregateHoursByYear(List<LogEntry> entries) {
    Map<String, double> result = {};
    for (var entry in entries) {
      String year = entry.date.year.toString();
      result[year] = (result[year] ?? 0) + entry.totalFlightTime;
    }
    return result;
  }

  Map<String, double> _aggregateByType(List<LogEntry> entries) {
    double night = 0, day = 0, instrument = 0, instructor = 0, cross = 0, solo = 0, dual = 0, pic = 0, sic = 0, examiner = 0, sim = 0, simI = 0, holds = 0;
    for (var entry in entries) {
      night += entry.nightTime;
      day += entry.dayTime;
      instrument += entry.actualInstruments;
      instructor += entry.instructor;
      cross += entry.crossCountryTime;
      solo += entry.soloTime;
      dual = entry.dualReceived;
      pic = entry.pilotInCommand;
      sic = entry.copilot;
      simI = entry.simulatedInstruments;
      examiner = entry.examiner;
      sim = entry.flightSimulator;
      holds += entry.holdingProcedures;
    }
    return {
      'Solo': solo,
      'Dual': dual,
      'Instructor': instructor,
      'Examiner': examiner,
      'PIC': pic,
      'SIC': sic,
      'Day': day,
      'Night': night,
      'Inst.': instrument,
      'Sim. Inst.': simI,
      'XC': cross,
      'Hold': holds,
      'Flt. Sim.': sim,
    };
  }

  Map<String, double> _aggregateByProcedure(List<LogEntry> entries) {
    double night = 0, day = 0, approaches = 0;
    for (var entry in entries) {
      night += entry.nightLandings;
      day += entry.dayLandings;
      approaches += entry.instrumentApproaches;
    }
    return {
      'Day Land': day,
      'Night Land': night,
      'Approaches': approaches,
    };
  }

  Map<String, double> _aggregateByMakeModel(List<LogEntry> entries) {
    Map<String, double> result = {};
    for (var entry in entries) {
      String key = entry.aircraftMakeModel;
      result[key] = (result[key] ?? 0) + entry.totalFlightTime;
    }
    return result;
  }

  Map<String, double> _aggregateByTailNumber(List<LogEntry> entries) {
    Map<String, double> result = {};
    for (var entry in entries) {
      String tail = entry.aircraftIdentification;
      result[tail] = (result[tail] ?? 0) + entry.totalFlightTime;
    }
    return result;
  }

  Widget _buildMultiSelectFilter<T>(
      String title, Set<T> selected, List<T> options) {
    return ExpansionTile(
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
      children: options.map((opt) {
        return CheckboxListTile(
          title: Text(opt.toString()),
          value: selected.contains(opt),
          onChanged: (val) {
            setState(() {
              if (val == true) {
                selected.add(opt);
              } else {
                selected.remove(opt);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildBarChart(Map<String, double> data, String title) {
    final entries = data.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        SizedBox(
          height: 200,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: entries.length * 80.0,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index < entries.length) {
                            return Transform.rotate(angle: -30 * pi / 180, child: Text(
                              entries[index].key,
                              style: TextStyle(fontSize: 10),
                            ));
                          }
                          return Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(entries.length, (index) {
                    return BarChartGroupData(x: index, barRods: [
                      BarChartRodData(
                          toY: entries[index].value,
                          color: Colors.blue,
                          width: 20)
                    ]);
                  }),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFlightList(List<LogEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries
          .map((e) => ListTile(
        title: Text('${e.aircraftMakeModel} (${e.aircraftIdentification})'),
        subtitle: Text(
            '${e.date.toLocal().toIso8601String().split("T")[0]} - ${e.totalFlightTime.toStringAsFixed(2)} hrs'),
      ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allYears = widget.logEntries.map((e) => e.date.year.toString()).toSet().toList();
    final allMakeModels = widget.logEntries
        .map((e) => e.aircraftMakeModel)
        .toSet()
        .toList();
    final allTails = widget.logEntries.map((e) => e.aircraftIdentification).toSet().toList();

    final filtered = filteredEntries;
    final hoursByYear = _aggregateHoursByYear(filtered);
    final hoursByType = _aggregateByType(filtered);
    final hoursByMakeModel = _aggregateByMakeModel(filtered);
    final hoursByTail = _aggregateByTailNumber(filtered);
    final byProcedure = _aggregateByProcedure(filtered);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMultiSelectFilter('Filter by Year', selectedYears, allYears),
          _buildMultiSelectFilter(
              'Filter by Aircraft Make & Model', selectedMakeModels, allMakeModels),
          _buildMultiSelectFilter(
              'Filter by Tail Number', selectedTails, allTails),
          _buildMultiSelectFilter(
              'Filter by Remark', selectedRemarks, ["Check", "IPC", "Review"]),
          SizedBox(height: 48),
          _buildBarChart(hoursByYear, 'Flight Hours by Year'),
          SizedBox(height: 48),
          _buildBarChart(hoursByMakeModel, 'Hours by Aircraft Make & Model'),
          SizedBox(height: 48),
          _buildBarChart(hoursByTail, 'Hours by Tail Number'),
          SizedBox(height: 48),
          _buildBarChart(hoursByType, 'Hours by Type'),
          SizedBox(height: 48),
          _buildBarChart(byProcedure, 'By Procedure'),
          SizedBox(height: 48),
          Text('Flights Matching Filters',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          _buildFlightList(filtered),
        ],
      ),
    );
  }
}
