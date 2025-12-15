import 'package:avaremp/aircraft.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/log_entry.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  AiScreenState createState() => AiScreenState();
}

class AiScreenState extends State<AiScreen> {

  final _model = FirebaseAI.vertexAI().generativeModel(model: 'gemini-2.5-pro', tools: [Tool.googleSearch()]); // connect with google search
  bool _isSending = false;
  final TextEditingController _editingController = TextEditingController();

  bool includePlan = false;
  bool includeAircraft = false;
  bool includeLogbook = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: UserDatabaseHelper.db.getAllAiQueries(),
      builder: (BuildContext context, AsyncSnapshot<List<(int, String)>?> snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return _makeContent(snapshot.data);
        }
        return Container();
      },
    );
  }

  Widget _makeContent(List<(int, String)>? data) {
    data ??= [];
    List<(int, String)> allQueries = data;

    Widget listOfContext = Row(children:[
      IconButton(tooltip: "Include the last 50 log book entries", onPressed: _isSending ? null :  () {setState(() {includeLogbook = !includeLogbook;});}, icon:Icon(Icons.notes, color: includeLogbook ? Colors.blueAccent : Colors.grey,)),
      IconButton(tooltip: "Include the tail number and the type of aircraft from the first aircraft in the aircraft list", onPressed: _isSending ? null : () {setState(() {includeAircraft = !includeAircraft;});}, icon:Icon(MdiIcons.airplane, color: includeAircraft ? Colors.blueAccent : Colors.grey,)),
      IconButton(tooltip: "Include the current plan, and the winds aloft from the departure and the destination airports of the plan", onPressed: _isSending ? null : () {setState(() {includePlan = !includePlan;});}, icon:Icon(Icons.route, color: includePlan ? Colors.blueAccent : Colors.grey,)),
    ]);

    Future<String> processQuery() async {
      String myQuery = _editingController.text;
      if(myQuery.isEmpty) {
        return "Please enter a question first";
      }
      if(myQuery.length > 128) {
        return "Question length must be less than 128 characters";
      }
      UserDatabaseHelper.db.insertAiQueries(myQuery);
      final prompt = TextPart(myQuery);
      List<Part> parts = [];
      parts.add(prompt);

      if(includeAircraft) {
        List<Aircraft> aircraft = await UserDatabaseHelper.db.getAllAircraft();
        if(aircraft.isNotEmpty) {
          Aircraft ac = aircraft.first;
          final acText = "Use aircraft ${ac.tail} and make/mode ${ac.type}";
          parts.add(TextPart(acText));
        }
      }
      if(includeLogbook) {
        List<LogEntry> entries = await UserDatabaseHelper.db.getAllLogbook();
        if(entries.isNotEmpty) {
          String logText = "Last 50 log book entries are:\n";
          logText += "${entries.first.toMap().keys.join(",")}\n";
          for(int i = 0; i < entries.length && i < 50; i++) {
            logText += "${entries[i].toMap().values.join(",")}\n";
          }
          parts.add(TextPart(logText));
        }
      }
      if(includePlan) {
        PlanRoute route = Storage().route;
        if(route.isNotEmpty) {
          String planText = "Plan is: ${route.toString()}\n";
          // winds
          LatLng start = route.getAllDestinations().first.coordinate;
          LatLng end = route.getAllDestinations().last.coordinate;
          String? windsStart = WindsCache.getWindsAtAll(start, 6);
          String? windsEnd = WindsCache.getWindsAtAll(end, 6);
          if(windsStart != null) {
            planText += "Winds at departure:\n$windsStart\n";
          }
          if(windsEnd != null) {
            planText += "Winds at destination:\n$windsStart\n";
          }
          parts.add(TextPart(planText));
        }
      }
      final query =  Content.multi(parts);
      final responseT = await _model.countTokens([query]);
      final totalTokens = responseT.totalTokens;
      if(totalTokens > 10000) {
        return "Please reduce the amount of context included to 10000 tokens - total tokens $totalTokens";
      }

      final response = await _model.generateContent([query]);
      if(response.text == null) {
        return "Error: no response from AI";
      }
      return response.text!;
    }

    Widget queryButton = _isSending ?  CircularProgressIndicator() : ElevatedButton(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30.0),
        ),
      ),
      onPressed: _isSending ? null : () async {
        setState(() {
          _isSending = true;
        });

        String responseText;
        try {
          responseText = await processQuery();
        }
        catch(e) {
          responseText = e.toString();
        }
        setState(() {
          _isSending = false;
          _editingController.text = responseText;
        });
      },
      child: Text("Ask")
    );

    Widget questions = PopupMenuButton(
      enabled: _isSending ? false : true,
      icon: Icon(Icons.more_horiz),
      tooltip: "Questions",
      itemBuilder: (context) => allQueries.map((query) {
          int id = query.$1;
          String item = query.$2;
          return PopupMenuItem<String>(
            value: item,
            padding: EdgeInsets.fromLTRB(0, 5, 0, 5),
            child: Padding(padding: EdgeInsets.fromLTRB(10, 0, 10, 0), child: Dismissible( // able to delete with swipe
                background: Container(alignment:
                Alignment.centerRight,child: const Icon(Icons.delete_forever),),
                key: Key(Storage().getKey()),
                direction: DismissDirection.endToStart,
                onDismissed:(direction) {
                    UserDatabaseHelper.db.deleteAiQuery(id).then((value) {
                      setState(() {});
                    });
                },
                child: ListTile(title: Text(item),
              )
            ))
          );
        }).toList(),
      onSelected: (value) {
        setState(() {
          _editingController.text = value;
        });
      },
    );

    TextField outputTextField = TextField(
      controller: _editingController,
      autofocus: true,
      enabled: _isSending == false,
      enableInteractiveSelection: true,
      maxLines: null,
      decoration: InputDecoration(
        border: InputBorder.none
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Flight Intelligence"),
        actions: [Tooltip(
            showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap,
            message:
"""
Ask AI anything about your flying -

Type your question in the box, or tap ... to choose from suggested questions.

Add context to get better answers:
Logbook — include your 50 most recent logbook entries
Aircraft — include details from your first aircraft
Plan — include your current flight plan

Tap any context item to highlight it.
Highlighted context will be sent along with the question.

Tap Ask to send your question to AI.
""",
            child: Icon(Icons.info))],
      ),
      body: Padding(padding: EdgeInsets.all(10), child:Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 17, child: Stack(children:[
            outputTextField,
            Align(alignment: Alignment.bottomRight, child:queryButton),
            Align(alignment: Alignment.bottomCenter, child:questions),
            Align(alignment: Alignment.topRight, child:IconButton(onPressed: () {setState(() {
              _editingController.text = "";
            });}, icon: Opacity(opacity: 0.7, child:Icon(Icons.backspace))))])),
            Divider(),
            Expanded(flex: 1, child: Text("Put context in the question:")),
            Expanded(flex: 2, child: listOfContext),
        ],
      ),
    ));
  }
}



