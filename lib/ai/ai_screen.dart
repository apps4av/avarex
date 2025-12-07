import 'package:avaremp/map_screen.dart';
import 'package:avaremp/services/backup_screen.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  AiScreenState createState() => AiScreenState();
}

class AiScreenState extends State<AiScreen> {

  final _model = FirebaseAI.vertexAI().generativeModel(model: 'gemini-2.5-pro');
  bool _isSending = false;
  final TextEditingController _editingControllerOutput = TextEditingController();
  final TextEditingController _editingControllerQuery = TextEditingController();
  final List<String> _typicalQueries = [
      'Based on the current flight plan, find best altitude fuel wise',
      'Based on the current flight plan, what are good alternates along the route',
      'Based on the current flight plan, check terrain clearance along the route',
      'Based on the current flight plan, suggest IFR or VFR',
      'How do I maintain instrument currency',
      'What are the night flight requirements',
      'What are the required documents to carry in the aircraft',
      'What are the VFR weather minimums for Class D airspace',
      'What are the fuel requirements for VFR flight during the day',
      'What are the fuel requirements for VFR flight at night',
      'What are the IFR fuel requirements',
      'What are the required reports to ATC when on an IFR flight plan',
      'What are the VFR weather minimums for Class E airspace',
      'When do I need an alternate airport on an IFR flight plan',
      'What are the currency requirements for carrying passengers',
      'What are the required tests and inspections for IFR operations',
      'What are the lost communication procedures for an IFR flight',
      'What are the lost communication procedures for a VFR flight',
      'Looking at my log book, am I instrument current',
      'Looking at my log book, how many night landings in the last 90 days',
      'Looking at my log book, how many IFR approaches in the last 6 months',
      'Looking at my log book, when does my instrument currency expire?',
      'Looking at my log book, what is the total PIC time in the last 6 months',
      'Looking at my log book, what are the total flight hours this year',
      'Looking at my log book, which aircraft do I fly the most',
      'Looking at my log book, show my most recent flight details',
      'From the given POH, describe the electrical system',
      'From the given POH, give the weight and balance limits',
      'From the given POH, what are the V-speeds',
      'From the given POH, describe the fuel system',
      'From the given POH, am I allowed to perform spins',
      'From the given POH, what are the emergency procedures for engine failure',
      'From the given POH, what are the normal procedures for takeoff',
      'From the given POH, what are the recommended cruise settings',
  ];

  bool includePlan = false;
  bool includePoh = false;
  bool includeLogbook = false;

  @override
  Widget build(BuildContext context) {

    Widget inputTextField;

    Widget listOfFiles = Row(children:[
      Padding(padding:EdgeInsets.all(5), child:InkWell(onTap: _isSending ? null :  () {setState(() {includeLogbook = !includeLogbook;});}, child:Text("Log Book", style:TextStyle(decoration: TextDecoration.underline, fontWeight: includeLogbook ? FontWeight.bold : FontWeight.normal)))),
      Padding(padding:EdgeInsets.all(5), child:InkWell(onTap: _isSending ? null : () {setState(() {includePoh = !includePoh;});}, child:Text("POH", style:TextStyle(decoration: TextDecoration.underline, fontWeight: includePoh ? FontWeight.bold : FontWeight.normal)))),
      Padding(padding:EdgeInsets.all(5), child:InkWell(onTap: _isSending ? null : () {setState(() {includePlan = !includePlan;});}, child:Text("Plan", style:TextStyle(decoration: TextDecoration.underline, fontWeight: includePlan ? FontWeight.bold : FontWeight.normal)))),
      if(includePlan || includeLogbook || includePoh) Expanded(flex: 2, child: Padding(padding: EdgeInsets.all(10),
          child:TextButton(onPressed: _isSending ? null : () {
            Navigator.pushNamed(context, '/backup');
          }, child: const Text("Upload Context"))
      )),

    ]);

    Future<String> processQuery() async {
      String myQuery = _editingControllerQuery.text;
      final prompt = TextPart(myQuery);
      List<Part> parts = [];
      parts.add(prompt);

      // context based parts
      List<String> files = await BackupScreenState.getFileList();
      for(String file in files) {
        if(file.endsWith(BackupScreenState.dbRefPoh) && includePoh) {
          FileData filePart = FileData(
              "application/pdf", file);
          parts.add(filePart);
        }
        else if(file.endsWith(BackupScreenState.dbRefLogbook) && includeLogbook) {
          FileData filePart = FileData(
              "text/plain", file);
          parts.add(filePart);
        }
        else if(file.endsWith(BackupScreenState.dbRefPlan) && includePlan) {
          FileData filePart = FileData(
              "text/plain", file);
          parts.add(filePart);
        }
      }
      final query =  Content.multi(parts);
      final responseT = await _model.countTokens([query]);
      final totalTokens = responseT.totalTokens;
      if(totalTokens > 5000) {
        if(context.mounted) {
          MapScreenState.showToast(context,
              "Please reduce the amount of context included - total tokens used $totalTokens",
              Icon(Icons.error, color: Colors.red), 5);
        }
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
          _editingControllerOutput.text = "";
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
          _editingControllerOutput.text = responseText;
        });
      },
      child: Text("Ask")
    );

    Widget questions = PopupMenuButton(
      icon: Icon(Icons.question_mark),
      itemBuilder: (context) => _typicalQueries.map((String item) {
          return PopupMenuItem<String>(
            value: item,
            padding: EdgeInsets.fromLTRB(0, 5, 0, 5),
            child: Row(children:[
              Expanded(child: Text(item)),
            ])
          );
        }).toList(),
      onSelected: (value) {
        setState(() {
          _editingControllerQuery.text = value;
          _editingControllerOutput.text = "";
        });
      },
    );

    inputTextField = TextField(
        enabled: _isSending == false,
        controller: _editingControllerQuery, maxLength: 128,
        decoration: InputDecoration(
            prefixIcon: questions,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(
                width: 1,
                style: BorderStyle.solid,
              ),
            ),
            suffixIcon: Container(
                margin: EdgeInsets.all(10),
                child: queryButton
            )
        )
    );

    TextField outputTextField = TextField(
      controller: _editingControllerOutput,
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
      ),
      body: Padding(padding: EdgeInsets.all(10), child:Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: inputTextField),
          Expanded(flex: 1, child: Text("Put context in the question (select to include): ")),
          Expanded(flex: 2, child: listOfFiles),
          Divider(),
          Expanded(flex: 15, child: outputTextField),
        ],
      ),
    ));
  }
}



