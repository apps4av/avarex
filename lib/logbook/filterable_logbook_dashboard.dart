import 'dart:math';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'log_entry.dart';

class FilterableLogbookDashboard extends StatefulWidget {
  final List<LogEntry> logEntries;

  const FilterableLogbookDashboard({super.key, required this.logEntries});

  @override
  FilterableLogbookDashboardState createState() =>
      FilterableLogbookDashboardState();
}

class FilterableLogbookDashboardState
    extends State<FilterableLogbookDashboard> {
  Set<String> selectedYears = {};
  Set<String> selectedMakeModels = {};
  Set<String> selectedTails = {};
  Set<String> selectedRemarks = {};
  bool _showFilters = false;

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
    var sortedKeys = result.keys.toList()..sort();
    return {for (var k in sortedKeys) k: result[k]!};
  }

  Map<String, double> _aggregateByType(List<LogEntry> entries) {
    double night = 0, day = 0, instrument = 0, instructor = 0, cross = 0, solo = 0, dual = 0, pic = 0, sic = 0, examiner = 0, sim = 0, simI = 0, holds = 0, ground = 0;
    for (var entry in entries) {
      night += entry.nightTime;
      day += entry.dayTime;
      instrument += entry.actualInstruments;
      instructor += entry.instructor;
      cross += entry.crossCountryTime;
      solo += entry.soloTime;
      dual += entry.dualReceived;
      pic += entry.pilotInCommand;
      sic += entry.copilot;
      simI += entry.simulatedInstruments;
      examiner += entry.examiner;
      sim += entry.flightSimulator;
      ground += entry.groundTime;
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
      'Actual IMC': instrument,
      'Sim. IMC': simI,
      'XC': cross,
      'Holds': holds,
      'Simulator': sim,
      'Ground': ground,
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
      'Day Landings': day,
      'Night Landings': night,
      'Approaches': approaches,
    };
  }

  Map<String, double> _aggregateByMakeModel(List<LogEntry> entries) {
    Map<String, double> result = {};
    for (var entry in entries) {
      String key = entry.aircraftMakeModel;
      if (key.isNotEmpty) {
        result[key] = (result[key] ?? 0) + entry.totalFlightTime;
      }
    }
    return result;
  }

  Map<String, double> _aggregateByTailNumber(List<LogEntry> entries) {
    Map<String, double> result = {};
    for (var entry in entries) {
      String tail = entry.aircraftIdentification;
      if (tail.isNotEmpty) {
        result[tail] = (result[tail] ?? 0) + entry.totalFlightTime;
      }
    }
    return result;
  }

  Widget _buildFilterChips(String title, Set<String> selected, List<String> options) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: options.map((opt) {
            final isSelected = selected.contains(opt);
            return FilterChip(
              label: Text(opt, style: TextStyle(fontSize: 12)),
              selected: isSelected,
              onSelected: (val) {
                setState(() {
                  if (val) {
                    selected.add(opt);
                  } else {
                    selected.remove(opt);
                  }
                });
              },
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildBarChart(Map<String, double> data, String title, {Color? barColor}) {
    final entries = data.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final color = barColor ?? Theme.of(context).colorScheme.primary;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: max(entries.length * 60.0, MediaQuery.of(context).size.width - 64),
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: entries.map((e) => e.value).reduce(max) * 1.2,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipPadding: const EdgeInsets.all(8),
                          tooltipMargin: 8,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              '${entries[group.x].key}\n${rod.toY.toStringAsFixed(1)}',
                              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              if (value == meta.max || value == 0) return const SizedBox.shrink();
                              return Text(value.toInt().toString(), style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline));
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              int index = value.toInt();
                              if (index < entries.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Transform.rotate(
                                    angle: -30 * pi / 180,
                                    child: Text(
                                      entries[index].key,
                                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(color: Theme.of(context).colorScheme.outlineVariant, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(entries.length, (index) {
                        return BarChartGroupData(x: index, barRods: [
                          BarChartRodData(
                            toY: entries[index].value,
                            color: color,
                            width: 24,
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                          )
                        ]);
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(List<LogEntry> entries) {
    double totalHours = entries.fold(0.0, (sum, e) => sum + e.totalFlightTime);
    int totalLandings = entries.fold(0, (sum, e) => sum + e.dayLandings + e.nightLandings);
    int totalApproaches = entries.fold(0, (sum, e) => sum + e.instrumentApproaches);
    double picHours = entries.fold(0.0, (sum, e) => sum + e.pilotInCommand);
    double nightHours = entries.fold(0.0, (sum, e) => sum + e.nightTime);
    double xcHours = entries.fold(0.0, (sum, e) => sum + e.crossCountryTime);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text("Summary", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                const Spacer(),
                Text("${entries.length} flights", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildSummaryTile("Total", totalHours.toStringAsFixed(1), "hrs", Icons.access_time)),
                Expanded(child: _buildSummaryTile("PIC", picHours.toStringAsFixed(1), "hrs", Icons.person)),
                Expanded(child: _buildSummaryTile("Night", nightHours.toStringAsFixed(1), "hrs", Icons.nights_stay)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildSummaryTile("XC", xcHours.toStringAsFixed(1), "hrs", Icons.route)),
                Expanded(child: _buildSummaryTile("Landings", totalLandings.toString(), "", Icons.flight_land)),
                Expanded(child: _buildSummaryTile("Approaches", totalApproaches.toString(), "", Icons.compass_calibration)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTile(String label, String value, String unit, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (unit.isNotEmpty) Text(" $unit", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          ],
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }

  Widget _buildCurrencyCard(List<LogEntry> allEntries) {
    final now = DateTime.now();
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));
    final sixMonthsAgo = now.subtract(const Duration(days: 180));
    
    final recent90 = allEntries.where((e) => e.date.isAfter(ninetyDaysAgo)).toList();
    
    int dayLandings90 = recent90.fold(0, (sum, e) => sum + e.dayLandings);
    int nightLandings90 = recent90.fold(0, (sum, e) => sum + e.nightLandings);
    int approaches6mo = allEntries.where((e) => e.date.isAfter(sixMonthsAgo)).fold(0, (sum, e) => sum + e.instrumentApproaches);
    
    bool dayCurrent = dayLandings90 >= 3;
    bool nightCurrent = nightLandings90 >= 3;
    bool ifrCurrent = approaches6mo >= 6;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text("Currency Status", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildCurrencyTile("Day (90 days)", "$dayLandings90/3 ldg", dayCurrent)),
                Expanded(child: _buildCurrencyTile("Night (90 days)", "$nightLandings90/3 ldg", nightCurrent)),
                Expanded(child: _buildCurrencyTile("IFR (6 months)", "$approaches6mo/6 app", ifrCurrent)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyTile(String label, String value, bool isCurrent) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.green.withAlpha(30) : Colors.orange.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isCurrent ? Colors.green : Colors.orange),
      ),
      child: Column(
        children: [
          Icon(isCurrent ? Icons.check_circle : Icons.warning, color: isCurrent ? Colors.green : Colors.orange, size: 24),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildFlightList(List<LogEntry> entries) {
    if (entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text("No flights match the selected filters", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text("Flight Log", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                const Spacer(),
                Text("${entries.length} entries", style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            ...entries.take(20).map((e) => Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Column(
                      children: [
                        Text(e.totalFlightTime.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                        Text("hrs", style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${e.aircraftMakeModel} (${e.aircraftIdentification})", style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text("${e.date.toString().substring(0,10)} • ${e.route}", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Text("D:${e.dayLandings} N:${e.nightLandings}", style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            )),
            if (entries.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(child: Text("+ ${entries.length - 20} more entries", style: TextStyle(color: Theme.of(context).colorScheme.outline))),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allYears = widget.logEntries.map((e) => e.date.year.toString()).toSet().toList()..sort();
    final allMakeModels = widget.logEntries.map((e) => e.aircraftMakeModel).where((m) => m.isNotEmpty).toSet().toList()..sort();
    final allTails = widget.logEntries.map((e) => e.aircraftIdentification).where((t) => t.isNotEmpty).toSet().toList()..sort();

    final filtered = filteredEntries;
    final hoursByYear = _aggregateHoursByYear(filtered);
    final hoursByType = _aggregateByType(filtered);
    final hoursByMakeModel = _aggregateByMakeModel(filtered);
    final hoursByTail = _aggregateByTailNumber(filtered);
    final byProcedure = _aggregateByProcedure(filtered);

    final hasFilters = selectedYears.isNotEmpty || selectedMakeModels.isNotEmpty || selectedTails.isNotEmpty || selectedRemarks.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCurrencyCard(widget.logEntries),
          _buildSummaryCard(filtered),

          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.filter_list, color: Theme.of(context).colorScheme.primary),
                  title: Text("Filters", style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasFilters)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              selectedYears.clear();
                              selectedMakeModels.clear();
                              selectedTails.clear();
                              selectedRemarks.clear();
                            });
                          },
                          child: const Text("Clear"),
                        ),
                      Icon(_showFilters ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                  onTap: () => setState(() => _showFilters = !_showFilters),
                ),
                if (_showFilters)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFilterChips('Year', selectedYears, allYears),
                        _buildFilterChips('Aircraft Type', selectedMakeModels, allMakeModels),
                        _buildFilterChips('Tail Number', selectedTails, allTails),
                        _buildFilterChips('Remarks', selectedRemarks, ["Check Ride", "IPC", "Flight Review", "Favorite"]),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          _buildBarChart(hoursByYear, 'Flight Hours by Year', barColor: Colors.blue),
          _buildBarChart(hoursByMakeModel, 'Hours by Aircraft Type', barColor: Colors.teal),
          _buildBarChart(hoursByTail, 'Hours by Tail Number', barColor: Colors.indigo),
          _buildBarChart(hoursByType, 'Hours by Category', barColor: Colors.deepPurple),
          _buildBarChart(byProcedure, 'Landings & Approaches', barColor: Colors.orange),

          const SizedBox(height: 8),
          _buildFlightList(filtered),
        ],
      ),
    );
  }
}
