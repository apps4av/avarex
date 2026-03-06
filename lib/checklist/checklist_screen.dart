import 'package:universal_io/io.dart';

import 'package:avaremp/checklist/checklist.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../constants.dart';

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});
  @override
  ChecklistScreenState createState() => ChecklistScreenState();
}

class ChecklistScreenState extends State<ChecklistScreen> {

  String? _selected;

  Widget _makeContent(List<Checklist>? items) {

    String inStorage = Storage().settings.getChecklist();

    if(null != items && items.isNotEmpty) {
      _selected = items[0].name; // use first item if nothing in storage
      for (Checklist c in items) {
        if (c.name == inStorage) { // found the checklist
          _selected = c.name;
        }
      }
    }

    return Scaffold(
        appBar: AppBar(
            backgroundColor: Constants.appBarBackgroundColor,
            title: Text(_selected == null ? "Check Lists" : _selected!),
            actions: _makeAction(items),
        ),
        body: _makeBody(items)
    );
  }

  List<Widget> _makeAction(List<Checklist>? items) {
    List<Widget> ret = [];
    ret.add(const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Import a text (.txt) checklist, with the first line as the title and the subsequent lines as the steps.", child: Icon(Icons.info)));
    ret.add(
      TextButton(onPressed: () {
        _pickFile().then((lines) => setState(() {
          if(lines.isEmpty) {
            return;
          }
          String name = lines.removeAt(0);
          int len = name.length;
          if(len == 0) {
            name = DateTime.now().toIso8601String();
          }
          else if(len > 24) {
            name = name.substring(0, 24);
          }
          // remove empty lines
          lines = List<String>.from(lines).where((value) => value.isNotEmpty).toList();
          Checklist list = Checklist(name, "", lines);
          UserDatabaseHelper.db.addChecklist(list);
        }));},
      child: const Text("Import")
    ));
    if(null == items || items.isEmpty) {
      return ret;
    }

    ret.addAll([
      Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        child: DropdownButtonHideUnderline(
            child: DropdownButton2<String>(
              isDense: true,// plate selection
              customButton: const Padding(padding: EdgeInsets.fromLTRB(10, 0, 10, 0), child: Icon(Icons.more_horiz)),
              buttonStyleData: ButtonStyleData(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
              ),
              dropdownStyleData: DropdownStyleData(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                width: Constants.screenWidth(context) / 2,
              ),
              isExpanded: false,
              value: _selected,
              items: items.map((Checklist e) => DropdownMenuItem<String>(value: e.name, child: Text(e.name, style: TextStyle(fontSize: Constants.dropDownButtonFontSize)))).toList(),
              onChanged: (value) {
                setState(() {
                  _selected = value;
                  Storage().settings.setChecklist(value!);
                });
              },
            )
        )
    )]);

    return ret;
  }

  (int, int) _getProgress() {
    int completed = 0;
    int total = Storage().activeChecklistSteps.length;
    for(int i = 0; i < total; i++) {
      if(Storage().activeChecklistSteps[i]) {
        completed++;
      }
    }
    return (completed, total);
  }

  Widget _makeBody(List<Checklist>? items) {

    Checklist active = Checklist.empty();
    if(null != _selected && null != items) {
      for (Checklist a in items) {
        if (a.name == _selected) {
          active = a;
        }
      }
    }

    if(Storage().activeChecklistName != active.name) {
      Storage().activeChecklistName = active.name;
      Storage().activeChecklistSteps = List.generate(active.steps.length, (index) => false);
    }

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState1) {
        var (completed, total) = _getProgress();
        bool allDone = total > 0 && completed == total;

        return Column(
          children: [
            if(total > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: allDone ? Colors.green.withAlpha(50) : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: total > 0 ? completed / total : 0,
                          minHeight: 8,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(allDone ? Colors.green : Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "$completed / $total",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: allDone ? Colors.green : null,
                      ),
                    ),
                    if(completed > 0)
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: "Reset all",
                        onPressed: () {
                          setState1(() {
                            Storage().activeChecklistSteps = List.generate(active.steps.length, (index) => false);
                          });
                        },
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: active.steps.length + (_selected != null ? 1 : 0),
                itemBuilder: (context, index) {
                  if(index < active.steps.length) {
                    bool isChecked = Storage().activeChecklistSteps[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: isChecked ? Colors.green.withAlpha(30) : null,
                      child: CheckboxListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        title: Text(
                          active.steps[index],
                          style: TextStyle(
                            decoration: isChecked ? TextDecoration.lineThrough : null,
                            color: isChecked ? Theme.of(context).colorScheme.onSurface.withAlpha(150) : null,
                          ),
                        ),
                        value: isChecked,
                        activeColor: Colors.green,
                        onChanged: (value) {
                          setState1(() {
                            Storage().activeChecklistSteps[index] = value!;
                          });
                        },
                      ),
                    );
                  } else {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Dismissible(
                        key: GlobalKey(),
                        background: const Icon(Icons.delete_forever),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) {
                          String? entry = _selected;
                          if(null != entry) {
                            UserDatabaseHelper.db.deleteChecklist(entry);
                          }
                          Storage().settings.setChecklist("");
                          setState(() {
                            _selected = null;
                          });
                        },
                        child: const Column(children:[Icon(Icons.swipe_left), Text("Delete", style: TextStyle(fontSize: 8))])
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: UserDatabaseHelper.db.getAllChecklist(),
      builder: (BuildContext context, AsyncSnapshot<List<Checklist>?> snapshot) {
        if(snapshot.connectionState == ConnectionState.done) {
          return _makeContent(snapshot.data);
        }
        return Container();
      },
    );
  }

  Future<List<String>> _pickFile() async {
    List<String> lines = [];
    // pick a file with txt as extension
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ["txt"]);
    if (result != null) {
      String? path = result.files.single.path;
      if(path != null) {
        File file = File(path);
        // copy now
        lines = await file.readAsLines();
      }
    }
    return lines;
  }

}


