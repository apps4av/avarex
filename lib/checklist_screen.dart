import 'dart:io';

import 'package:avaremp/checklist.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'constants.dart';

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

  Color _checkRemaining() {
    Color color = Colors.transparent;
    int remaining = 0;
    for(int i = 0; i < Storage().activeChecklistSteps.length; i++) {
      if(!Storage().activeChecklistSteps[i]) {
        remaining++;
      }
    }
    if(remaining == 0) {
      // all done
      color = Colors.green.withAlpha(100);
    }
    return color;
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
      // store steps. create an array of size equal to current checklist size
      Storage().activeChecklistSteps = List.generate(active.steps.length, (index) => false);
    }

    Color bg = _checkRemaining();
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState1) {
        return SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // add list here
              for(int index = 0; index < active.steps.length; index++)
                Column(children:[
                  CheckboxListTile(tileColor: bg, title: Text(active.steps[index]), value: Storage().activeChecklistSteps[index], onChanged: (value) {
                    setState1(() {
                      Storage().activeChecklistSteps[index] = value!;
                      bg = _checkRemaining();
                    });
                  }),
                  const Divider()
                ]),
              if(_selected != null)
                Padding(padding: const EdgeInsets.all(20), child: Dismissible(key: GlobalKey(),
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
                    child: const Column(children:[Icon(Icons.swipe_left), Text("Delete", style: TextStyle(fontSize: 8))]))),
            ],
          )
        )
    );
  });}

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


