import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/aircraft.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/services/backup_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
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
      'From the given aircraft manual, describe the electrical system',
      'From the given aircraft manual, give the weight and balance limits',
      'From the given aircraft manual, what are the V-speeds',
      'From the given aircraft manual, describe the fuel system',
      'From the given aircraft manual, am I allowed to perform spins',
      'From the given aircraft manual, what are the emergency procedures for engine failure',
      'From the given aircraft manual, what are the normal procedures for takeoff',
      'From the given aircraft manual, what are the recommended cruise settings',
  ];

  @override
  Widget build(BuildContext context) {

    Widget inputTextField;

    Future<String> processQuery() async {
      String myQuery = _editingControllerQuery.text;
      final prompt = TextPart(myQuery);
      List<Part> parts = [];
      parts.add(prompt);

      // context based parts
      List<Destination> destinations = Storage().route.getAllDestinations();
      if(destinations.isNotEmpty) {
        final flightPlanPart = TextPart(
            "If needed, use the current flight plan:\n${Storage().route}");
        parts.add(flightPlanPart);
        String? winds = WindsCache.getWindsAtAll(destinations[0].coordinate, 6);
        if(winds != null) {
          final windsPart = TextPart("If needed, use winds aloft:\n$winds");
          parts.add(windsPart);
        }
        final List<Aircraft> aircraft = await UserDatabaseHelper.db.getAllAircraft();
        if(aircraft.isNotEmpty) {
          final aircraft1 = aircraft.first;
          final aircraftPart = TextPart("If needed use aircraft:\n ${jsonEncode(aircraft1.toMap())}");
          parts.add(aircraftPart);
        }
      }
      FileData filePart = FileData("text/plain", BackupScreen.getUserDataJsonPath());
      parts.add(filePart);
      filePart = FileData("application/pdf", BackupScreen.getAircraftPath());
      parts.add(filePart);
      final query =  Content.multi(parts);
      final response = await _model.generateContent([query]);
      if(response.text == null) {
        return "Error: no response from AI";
      }
      return response.text!;
    }

    ElevatedButton queryButton = ElevatedButton(
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

        String responseText = await processQuery();

        setState(() {
          _isSending = false;
          _editingControllerOutput.text = responseText;
        });
      },
      child: _isSending ?  CircularProgressIndicator() : Text("Ask")
    );

    Widget questions = DropdownButtonHideUnderline(child:DropdownButton2<String>(
      isDense: true,
      customButton: Icon(Icons.question_mark_outlined),
      buttonStyleData: ButtonStyleData(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
      ),
      dropdownStyleData: DropdownStyleData(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
        width: Constants.screenWidth(context) * 0.9,
      ),
      isExpanded: false,
      value: _typicalQueries[0],
      items: _typicalQueries.map((String item) {
        return DropdownMenuItem<String>(
            value: item,
            child: Row(children:[
              Expanded(child:
              Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),),
                  child: Padding(padding: const EdgeInsets.all(5), child:
                  AutoSizeText(item, minFontSize: 2, maxLines: 1),)),
              )
            ])
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _editingControllerQuery.text = value;
          _editingControllerOutput.text = "";
        });
      },
    ));

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
          Expanded(flex: 2, child: inputTextField),
          Expanded(flex: 2, child: Padding(padding: EdgeInsets.all(10),
              child:TextButton(child: const Text("Upload Query Context"),
                  onPressed: () {
                    Navigator.pushNamed(context, '/backup');
                  })
          )),
          Expanded(flex: 15, child: outputTextField),
        ],
      ),
    ));
  }
}



