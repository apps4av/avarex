import 'package:avaremp/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

import 'data/user_database_helper.dart';
import 'log_entry.dart';

// this is entirely AI generated code to manage a logbook

class LogbookScreen extends StatefulWidget {
  const LogbookScreen({super.key});

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen> {
  List<LogEntry> entries = [];
  double totalHours = 0.0;

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

    for (final row in dataRows) {
      final map = <String, dynamic>{};
      for (int i = 0; i < headers.length; i++) {
        final key = headers[i];
        final value = row[i];

        // Safely convert numeric fields
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

      final entry = LogEntry.fromJson(map);
      await UserDatabaseHelper.db.insertLogbook(entry);
    }

    _loadEntries();
    if(mounted) {
      MapScreenState.showToast(
          context, "CSV imported successfully", Icon(Icons.info, color: Colors.blue,), 3);
    }
  }

  Future<void> _exportCsv() async {
    final entries = await UserDatabaseHelper.db.getAllLogbook();

    if (entries.isEmpty) return;

    // use keys from toJson() for consistency
    final headers = entries.first.toJson().keys.toList();
    final rows = [
      headers,
      ...entries.map((e) => headers.map((h) => e.toJson()[h]).toList()),
    ];

    final csv = const ListToCsvConverter().convert(rows);

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/logbook_export.csv");
    await file.writeAsString(csv);

    final params = ShareParams(
      files: [XFile(file.path)],
      sharePositionOrigin: const Rect.fromLTWH(128, 128, 1, 1),
    );
    SharePlus.instance.share(params);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Log Book"),
        actions: [
          Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "You may import/export a log book from/to a CSV file. The first line of the file must be the header. Use Export to see the format.", child: Icon(Icons.info)),
          TextButton(onPressed: _importCsv, child: const Text("Import")),
          TextButton(onPressed: _exportCsv, child: const Text("Export")),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            title: const Text("Total Hours"),
            trailing: Text(totalHours.toStringAsFixed(1), style: const TextStyle(fontSize: 16)),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                return ListTile(
                  title: Text("${e.date.toString().substring(0, 10)} – ${e.aircraftIdentification} (${e.aircraftMakeModel})"),
                  subtitle: Text("${e.route} • ${e.totalFlightTime} hrs"),
                  onTap: () => _openForm(entry: e),
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

  // --- Controllers for all fields ---
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
      MapScreenState.showToast(
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
      instrumentApproaches: int.tryParse(_approachesController.text) ?? 0,
      instructorName: _instructorNameController.text,
      instructorCertificate: _instructorCertController.text,
      remarks: _remarksController.text,
    );

    widget.onSave(entry);
    Navigator.of(context).pop();
  }

  Widget _buildNumberField(String label, TextEditingController controller,
      {bool isInteger = false}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      validator: (v) {
        if (v == null || v.isEmpty) return "Required";
        return isInteger
            ? (int.tryParse(v) == null ? "Must be integer" : null)
            : (double.tryParse(v) == null ? "Must be number" : null);
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? "New Log Book Entry" : "Modify Log Book Entry"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _dateController,
                decoration: const InputDecoration(labelText: "Date (YYYY-MM-DD)"),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              TextFormField(
                controller: _aircraftMakeModelController,
                decoration: const InputDecoration(labelText: "Aircraft Make/Model"),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              TextFormField(
                controller: _aircraftIdController,
                decoration: const InputDecoration(labelText: "Aircraft ID"),
              ),
              TextFormField(
                controller: _routeController,
                decoration: const InputDecoration(labelText: "Route"),
              ),
              _buildNumberField("Total Flight Time (hrs)", _totalTimeController),
              _buildNumberField("Day Time (hrs)", _dayTimeController),
              _buildNumberField("Night Time (hrs)", _nightTimeController),
              _buildNumberField("Cross Country (hrs)", _crossCountryController),
              _buildNumberField("Solo Time (hrs)", _soloTimeController),
              _buildNumberField("Simulated Instruments (hrs)", _simInstrumentController),
              _buildNumberField("Actual Instruments (hrs)", _actualInstrumentController),
              _buildNumberField("Dual Received (hrs)", _dualReceivedController),
              _buildNumberField("Pilot In Command (hrs)", _picController),
              _buildNumberField("Copilot (hrs)", _copilotController),
              _buildNumberField("Instructor (hrs)", _instructorController),
              _buildNumberField("Examiner (hrs)", _examinerController),
              _buildNumberField("Flight Simulator (hrs)", _simulatorController),
              _buildNumberField("Day Landings", _dayLandingsController, isInteger: true),
              _buildNumberField("Night Landings", _nightLandingsController, isInteger: true),
              _buildNumberField("Holding Procedures (hrs)", _holdingController),
              _buildNumberField("Instrument Approaches", _approachesController, isInteger: true),
              TextFormField(
                controller: _instructorNameController,
                decoration: const InputDecoration(labelText: "Instructor Name"),
              ),
              TextFormField(
                controller: _instructorCertController,
                decoration: const InputDecoration(labelText: "Instructor Certificate"),
              ),
              TextFormField(
                controller: _remarksController,
                decoration: const InputDecoration(labelText: "Remarks"),
              ),

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

    final header = entries.first.toJson().keys.toList();

    final rows = [
      header,
      ...entries.map((e) {
        final map = e.toJson();
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
      return LogEntry.fromJson(row); // use fromJson
    }).toList();
  }
}

