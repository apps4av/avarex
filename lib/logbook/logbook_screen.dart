import 'package:avaremp/logbook/filterable_logbook_dashboard.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:universal_io/io.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

import '../data/user_database_helper.dart';
import 'log_entry.dart';

class LogbookScreen extends StatefulWidget {
  const LogbookScreen({super.key});

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen> {
  List<LogEntry> entries = [];
  double totalHours = 0.0;
  int totalLandings = 0;
  int totalApproaches = 0;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final list = await UserDatabaseHelper.db.getAllLogbook();
    setState(() {
      entries = list;
      totalHours = list.fold(0.0, (sum, e) => sum + (e.totalFlightTime));
      totalLandings = list.fold(0, (sum, e) => sum + e.dayLandings + e.nightLandings);
      totalApproaches = list.fold(0, (sum, e) => sum + e.instrumentApproaches);
    });
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null) return;

    final file = File(result.files.single.path!);
    final csvContent = await file.readAsString();

    final rows = const CsvToListConverter(eol: "\n")
        .convert(csvContent, shouldParseNumbers: false);

    if (rows.isEmpty) return;

    final headers = rows.first.cast<String>();
    final dataRows = rows.skip(1);

    bool error = false;
    for (final row in dataRows) {
      final map = <String, dynamic>{};
      for (int i = 0; i < headers.length; i++) {
        final key = headers[i];
        final value = row[i];

        if ([
          "totalFlightTime",
          "dayTime",
          "nightTime",
          "crossCountryTime",
          "soloTime",
          "simulatedInstruments",
          "actualInstruments",
          "dualReceived",
          "pilotInCommand",
          "copilot",
          "instructor",
          "examiner",
          "groundTime",
          "flightSimulator",
          "holdingProcedures"
        ].contains(key)) {
          map[key] = double.tryParse(value.toString()) ?? 0.0;
        } else if ([
          "dayLandings",
          "nightLandings",
          "instrumentApproaches"
        ].contains(key)) {
          map[key] = int.tryParse(value.toString()) ?? 0;
        } else {
          map[key] = value.toString();
        }
      }

      final LogEntry entry;
      try {
        entry = LogEntry.fromMap(map);
      }
      catch(e) {
        error = true;
        continue;
      }
      await UserDatabaseHelper.db.insertLogbook(entry);
    }

    _loadEntries();
    if(mounted) {
      if(error) {
        Toast.showToast(context, "Unable to import all or some of the CSV file",
            Icon(Icons.info, color: Colors.red,), 3);
      }
      else {
        Toast.showToast(
            context, "CSV imported successfully",
            Icon(Icons.info, color: Colors.blue,), 3);
      }
    }
  }

  Future<void> _exportCsv() async {
    final entries = await UserDatabaseHelper.db.getAllLogbook();

    if (entries.isEmpty) return;

    final headers = entries.first.toMap().keys.toList();
    final rows = [
      headers,
      ...entries.map((e) => headers.map((h) => e.toMap()[h]).toList()),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    String? path = await PathUtils.writeLogbook(Storage().dataDir, csv);

    if(path != null) {
      final params = ShareParams(
        files: [XFile(path)],
        title: PathUtils.filename(path),
        sharePositionOrigin: const Rect.fromLTWH(128, 128, 1, 1),
      );
      SharePlus.instance.share(params);
    }
    else {
      if(mounted) {
        Toast.showToast(
            context, "Failed to write CSV", Icon(Icons.error, color: Colors.red,), 3);
      }
    }
  }

  void _openForm({LogEntry? entry}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LogEntryForm(
        entry: entry,
        onSave: (saved) async {
          if (entry == null) {
            await UserDatabaseHelper.db.insertLogbook(saved);
          } else {
            await UserDatabaseHelper.db.updateLogbook(saved);
          }
          _loadEntries();
        },
        onDelete: (deleted) async {
          await UserDatabaseHelper.db.deleteLogbook(deleted.id);
          _loadEntries();
        },
      ),
    ));
  }

  void _openStats() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text('Log Book Dashboard')),
          body: FilterableLogbookDashboard(logEntries: entries),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Log Book"),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: "You may import/export a log book from/to a CSV file. The first line of the file must be the header. Use Export to see the format.",
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: "Import CSV",
            onPressed: _importCsv,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: "Export CSV",
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn("Total Hours", totalHours.toStringAsFixed(1), Icons.access_time),
                  _buildStatColumn("Landings", totalLandings.toString(), Icons.flight_land),
                  _buildStatColumn("Approaches", totalApproaches.toString(), Icons.compass_calibration),
                  IconButton.filled(
                    onPressed: _openStats,
                    icon: const Icon(Icons.analytics),
                    tooltip: "View Details",
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  "${entries.length} Entries",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.book_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text("No log entries yet", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => _openForm(),
                        icon: const Icon(Icons.add),
                        label: const Text("Add your first entry"),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              e.totalFlightTime.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            Text("hrs", style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                          ],
                        ),
                        title: Text(
                          "${e.aircraftMakeModel} (${e.aircraftIdentification})",
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 12, color: Theme.of(context).colorScheme.outline),
                                const SizedBox(width: 4),
                                Text(e.date.toString().substring(0, 10), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                              ],
                            ),
                            if(e.route.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.route, size: 12, color: Theme.of(context).colorScheme.outline),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(e.route, style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ],
                          ],
                        ),
                        trailing: Text(
                          "D:${e.dayLandings} N:${e.nightLandings}\nIAP:${e.instrumentApproaches}",
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.end,
                        ),
                        onTap: () => _openForm(entry: e),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _openForm(),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }

}


class LogEntryForm extends StatefulWidget {
  final LogEntry? entry;
  final void Function(LogEntry) onSave;
  final void Function(LogEntry) onDelete;

  const LogEntryForm({super.key, this.entry, required this.onSave, required this.onDelete});

  @override
  State<LogEntryForm> createState() => _LogEntryFormState();
}

class _LogEntryFormState extends State<LogEntryForm> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _dateController;
  late TextEditingController _aircraftMakeModelController;
  late TextEditingController _aircraftIdController;
  late TextEditingController _routeController;
  late TextEditingController _totalTimeController;
  late TextEditingController _dayTimeController;
  late TextEditingController _nightTimeController;
  late TextEditingController _crossCountryController;
  late TextEditingController _soloTimeController;
  late TextEditingController _simInstrumentController;
  late TextEditingController _actualInstrumentController;
  late TextEditingController _dualReceivedController;
  late TextEditingController _picController;
  late TextEditingController _copilotController;
  late TextEditingController _instructorController;
  late TextEditingController _examinerController;
  late TextEditingController _simulatorController;
  late TextEditingController _dayLandingsController;
  late TextEditingController _nightLandingsController;
  late TextEditingController _holdingController;
  late TextEditingController _groundTimeController;
  late TextEditingController _approachesController;
  late TextEditingController _instructorNameController;
  late TextEditingController _instructorCertController;
  late TextEditingController _remarksController;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    String date = "";
    if(e?.date != null) {
      date = e!.date.toString().substring(0,10);
    }
    _dateController = TextEditingController(text: date);
    _aircraftMakeModelController = TextEditingController(text: e?.aircraftMakeModel ?? "");
    _aircraftIdController = TextEditingController(text: e?.aircraftIdentification ?? "");
    _routeController = TextEditingController(text: e?.route ?? "");
    _totalTimeController = TextEditingController(text: e?.totalFlightTime.toString() ?? "0.0");
    _dayTimeController = TextEditingController(text: e?.dayTime.toString() ?? "0.0");
    _nightTimeController = TextEditingController(text: e?.nightTime.toString() ?? "0.0");
    _crossCountryController = TextEditingController(text: e?.crossCountryTime.toString() ?? "0.0");
    _soloTimeController = TextEditingController(text: e?.soloTime.toString() ?? "0.0");
    _simInstrumentController = TextEditingController(text: e?.simulatedInstruments.toString() ?? "0.0");
    _actualInstrumentController = TextEditingController(text: e?.actualInstruments.toString() ?? "0.0");
    _dualReceivedController = TextEditingController(text: e?.dualReceived.toString() ?? "0.0");
    _picController = TextEditingController(text: e?.pilotInCommand.toString() ?? "0.0");
    _copilotController = TextEditingController(text: e?.copilot.toString() ?? "0.0");
    _instructorController = TextEditingController(text: e?.instructor.toString() ?? "0.0");
    _examinerController = TextEditingController(text: e?.examiner.toString() ?? "0.0");
    _simulatorController = TextEditingController(text: e?.flightSimulator.toString() ?? "0.0");
    _dayLandingsController = TextEditingController(text: e?.dayLandings.toString() ?? "0");
    _nightLandingsController = TextEditingController(text: e?.nightLandings.toString() ?? "0");
    _holdingController = TextEditingController(text: e?.holdingProcedures.toString() ?? "0.0");
    _groundTimeController = TextEditingController(text: e?.groundTime.toString() ?? "0.0");
    _approachesController = TextEditingController(text: e?.instrumentApproaches.toString() ?? "0");
    _instructorNameController = TextEditingController(text: e?.instructorName ?? "");
    _instructorCertController = TextEditingController(text: e?.instructorCertificate ?? "");
    _remarksController = TextEditingController(text: e?.remarks ?? "");
  }

  @override
  void dispose() {
    _dateController.dispose();
    _aircraftMakeModelController.dispose();
    _aircraftIdController.dispose();
    _routeController.dispose();
    _totalTimeController.dispose();
    _dayTimeController.dispose();
    _nightTimeController.dispose();
    _crossCountryController.dispose();
    _soloTimeController.dispose();
    _simInstrumentController.dispose();
    _actualInstrumentController.dispose();
    _dualReceivedController.dispose();
    _picController.dispose();
    _copilotController.dispose();
    _instructorController.dispose();
    _examinerController.dispose();
    _simulatorController.dispose();
    _dayLandingsController.dispose();
    _nightLandingsController.dispose();
    _holdingController.dispose();
    _approachesController.dispose();
    _instructorNameController.dispose();
    _instructorCertController.dispose();
    _groundTimeController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  void _delete() {
    if (!_formKey.currentState!.validate()) return;
    widget.onDelete(widget.entry!);
    Navigator.of(context).pop();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    String dateText = _dateController.text;
    DateTime? dt = DateTime.tryParse(dateText);
    if(dt == null) {
      Toast.showToast(
          context, "Invalid date format", Icon(Icons.error, color: Colors.red,), 3);
      return;
    }

    final entry = LogEntry(
      id: widget.entry?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      date: dt,
      aircraftMakeModel: _aircraftMakeModelController.text,
      aircraftIdentification: _aircraftIdController.text,
      route: _routeController.text,
      totalFlightTime: double.tryParse(_totalTimeController.text) ?? 0.0,
      dayTime: double.tryParse(_dayTimeController.text) ?? 0.0,
      nightTime: double.tryParse(_nightTimeController.text) ?? 0.0,
      crossCountryTime: double.tryParse(_crossCountryController.text) ?? 0.0,
      soloTime: double.tryParse(_soloTimeController.text) ?? 0.0,
      simulatedInstruments: double.tryParse(_simInstrumentController.text) ?? 0.0,
      actualInstruments: double.tryParse(_actualInstrumentController.text) ?? 0.0,
      dualReceived: double.tryParse(_dualReceivedController.text) ?? 0.0,
      pilotInCommand: double.tryParse(_picController.text) ?? 0.0,
      copilot: double.tryParse(_copilotController.text) ?? 0.0,
      instructor: double.tryParse(_instructorController.text) ?? 0.0,
      examiner: double.tryParse(_examinerController.text) ?? 0.0,
      flightSimulator: double.tryParse(_simulatorController.text) ?? 0.0,
      dayLandings: int.tryParse(_dayLandingsController.text) ?? 0,
      nightLandings: int.tryParse(_nightLandingsController.text) ?? 0,
      holdingProcedures: double.tryParse(_holdingController.text) ?? 0.0,
      groundTime: double.tryParse(_groundTimeController.text) ?? 0.0,
      instrumentApproaches: int.tryParse(_approachesController.text) ?? 0,
      instructorName: _instructorNameController.text,
      instructorCertificate: _instructorCertController.text,
      remarks: _remarksController.text,
    );

    widget.onSave(entry);
    Navigator.of(context).pop();
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: required ? (v) => v == null || v.isEmpty ? "Required" : null : null,
      ),
    );
  }

  Widget _buildNumberField(String label, TextEditingController controller, {bool isInteger = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        keyboardType: TextInputType.number,
        validator: (v) {
          if (v == null || v.isEmpty) return "Required";
          return isInteger
              ? (int.tryParse(v) == null ? "Must be integer" : null)
              : (double.tryParse(v) == null ? "Must be number" : null);
        },
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? "New Log Book Entry" : "Edit Log Book Entry"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildSection("Flight Info", Icons.flight, [
                _buildTextField("Date (YYYY-MM-DD)", _dateController, required: true),
                _buildTextField("Aircraft Tail Number", _aircraftIdController),
                _buildTextField("Aircraft Type", _aircraftMakeModelController, required: true),
                _buildTextField("Route", _routeController),
              ]),

              _buildSection("Flight Time", Icons.access_time, [
                Row(
                  children: [
                    Expanded(child: _buildNumberField("Total (hrs)", _totalTimeController)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField("Day (hrs)", _dayTimeController)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField("Night (hrs)", _nightTimeController)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildNumberField("Cross Country", _crossCountryController)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField("Solo", _soloTimeController)),
                  ],
                ),
              ]),

              _buildSection("Pilot Function", Icons.person, [
                Row(
                  children: [
                    Expanded(child: _buildNumberField("PIC (hrs)", _picController)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField("SIC (hrs)", _copilotController)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildNumberField("Dual Received", _dualReceivedController)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField("Instructor", _instructorController)),
                  ],
                ),
                _buildNumberField("Examiner (hrs)", _examinerController),
              ]),

              _buildSection("Instrument", Icons.compass_calibration, [
                Row(
                  children: [
                    Expanded(child: _buildNumberField("Actual IMC", _actualInstrumentController)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField("Simulated", _simInstrumentController)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildNumberField("Approaches", _approachesController, isInteger: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField("Holds", _holdingController)),
                  ],
                ),
              ]),

              _buildSection("Landings", Icons.flight_land, [
                Row(
                  children: [
                    Expanded(child: _buildNumberField("Day Landings", _dayLandingsController, isInteger: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField("Night Landings", _nightLandingsController, isInteger: true)),
                  ],
                ),
              ]),

              _buildSection("Training & Simulation", Icons.school, [
                Row(
                  children: [
                    Expanded(child: _buildNumberField("Ground Time", _groundTimeController)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField("Simulator", _simulatorController)),
                  ],
                ),
                _buildTextField("Instructor Name", _instructorNameController),
                _buildTextField("Instructor Certificate", _instructorCertController),
              ]),

              _buildSection("Remarks", Icons.notes, [
                TextFormField(
                  controller: _remarksController,
                  decoration: const InputDecoration(
                    labelText: "Remarks",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ]),

              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Padding(padding: const EdgeInsets.all(20), child: Dismissible(key: GlobalKey(),
                        background: const Icon(Icons.delete_forever),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) {
                          _delete();
                        },
                        child: const Column(children:[Icon(Icons.swipe_left), Text("Delete", style: TextStyle(fontSize: 8))])
                    )),

                    TextButton(
                        onPressed: () {
                          _save();
                        },
                        child: const Text("Save")
                    ),
                  ]))
            ],
          ),
        ),
      ),
    );
  }
}

class LogbookCsv {
  static String exportCsv(List<LogEntry> entries) {
    if (entries.isEmpty) return "";

    final header = entries.first.toMap().keys.toList();

    final rows = [
      header,
      ...entries.map((e) {
        final map = e.toMap();
        return header.map((h) => map[h] ?? "").toList();
      }),
    ];

    return const ListToCsvConverter().convert(rows);
  }

  static List<LogEntry> importCsv(String csvContent) {
    final rows = const CsvToListConverter().convert(csvContent, eol: "\n");
    if (rows.isEmpty) return [];

    final header = rows.first.cast<String>();
    final data = rows.skip(1);

    return data.map((r) {
      final row = Map<String, dynamic>.fromIterables(header, r);
      return LogEntry.fromMap(row);
    }).toList();
  }
}
