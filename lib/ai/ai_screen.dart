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
  final TextEditingController _editingController = TextEditingController();
  final TextEditingController _editingControllerQuestion = TextEditingController();
  final List<String> _categories = [
    'Flight plan',
    'Log book',
    'Aircraft',
    'Tracks',
    'FAA',
  ];
  String _selectedCategory = 'Flight plan';
  final Map<String, List<String>> _typicalQueriesByCategory = {
    'Flight plan': [
      'Is this a valid plan?',
      'Find best altitude fuel wise',
      'Find best altitude for lowest fuel burn',
      'Estimate time en route and fuel',
      'What are good alternates along this route?',
      'Check terrain clearance along route',
      'Summarize route and winds',
      'Suggest IFR or VFR for this plan',
      'Find minimum fuel stop plan',
      'Compute great-circle distance for this route',
      'Recommend cruise altitude by winds and terrain',
    ],
    'FAA': [
      'How do I maintain instrument currency?',
      'What are the night flight requirements?',
      'What are the required documents to carry in the aircraft?',
      'What are the VFR weather minimums for Class D airspace?',
      'What are the fuel requirements for VFR flight during the day?',
      'What are the fuel requirements for VFR flight at night?',
      'What are the required inspections for a private aircraft?',
      'What are the IFR fuel requirements?',
      'What are the minimums to shoot an ILS approach?',
      'What are the required reports to ATC when on an IFR flight plan?',
      'What are the VFR weather minimums for Class E airspace?',
      'What are the VFR weather minimums for Class G airspace?',
      'When do I need an alternate airport on an IFR flight plan?',
      'What are the currency requirements for carrying passengers?',
      'What are the required tests and inspections for IFR operations?',
      'What are the lost communication procedures for an IFR flight?',
      'What are the lost communication procedures for a VFR flight?',
    ],
    'Log book': [
      'Am I instrument current?',
      'How many night landings in the last 90 days?',
      'How many IFR approaches in the last 6 months?',
      'When does my instrument currency expire?',
      'Total PIC time in the last 6 months',
      'Total flight hours this year',
      'Totals by aircraft make/model',
      'Which aircraft do I fly most?',
      'Show my most recent flight details',
    ],
    'Aircraft': [
      'Describe the electrical system',
      'Give the weight and balance limits',
      'What are the V-speeds?',
      'Describe the fuel system',
      'Can I perform spins in it?',
      'What are the emergency procedures for engine failure?',
      'What are the emergency procedures for electrical failure?',
      'What are the normal procedures for takeoff?',
      'What are the normal procedures for landing?',
      'What are the performance numbers for takeoff?',
      'What are the performance numbers for landing?',
      'What are the recommended climb speeds?',
      'What are the recommended cruise settings?',
    ],
    'Tracks': [
      'Summarize my last flight',
      'What was my average ground speed?',
      'What was my maximum altitude?',
      'How long was my last flight?',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flight Intelligence"),
      ),
      body: Padding(padding: EdgeInsets.all(10), child:Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 1,
              child: Row(children: [
                Padding(padding: EdgeInsets.all(10), child:DropdownButtonHideUnderline(child:DropdownButton2<String>(
                  isDense: true,
                  customButton: AutoSizeText(_selectedCategory, style: TextStyle(fontWeight: FontWeight.bold,)),
                  buttonStyleData: ButtonStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                    width: Constants.screenWidth(context) * 0.3,
                  ),
                  isExpanded: false,
                  value: _categories[0],
                  items: _categories.map((String item) {
                    return DropdownMenuItem<String>(
                        value: item,
                        child: Row(children:[
                          Expanded(child:
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),),
                            child: Padding(padding: const EdgeInsets.all(5), child:
                            AutoSizeText(item, minFontSize: 2, maxLines: 1,)),
                          ))
                        ])
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedCategory = value;
                      _editingController.text = "";
                      _editingControllerQuestion.text = _typicalQueriesByCategory[_selectedCategory]![0];
                    });
                  },
                )
              )),
              Padding(padding: EdgeInsets.all(10), child: DropdownButtonHideUnderline(child:DropdownButton2<String>(
                  isDense: true,
                  customButton: Icon(Icons.more_horiz),
                  buttonStyleData: ButtonStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                    width: Constants.screenWidth(context) * 0.9,
                  ),
                  isExpanded: false,
                  value: _typicalQueriesByCategory[_selectedCategory]![0],
                  items: _typicalQueriesByCategory[_selectedCategory]!.map((String item) {
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
                      _editingControllerQuestion.text = value;
                      _editingController.text = "";
                    });
                  },
                )
                )),
                Padding(padding: EdgeInsets.all(10),
                  child:TextButton(child: const Text("Context"),
                      onPressed: () {
                        // route based on category
                        if(_selectedCategory == 'Flight plan') {
                          Navigator.pushNamed(context, '/plan_actions');
                        }
                        else if(_selectedCategory == 'Log book') {
                          Navigator.pushNamed(context, '/backup');
                        }
                        else if(_selectedCategory == 'Aircraft') {
                          Navigator.pushNamed(context, '/backup');
                        }
                        else if(_selectedCategory == 'Tracks') {
                          Navigator.pushNamed(context, '/backup');
                        }
                      })
                  ),
              ])
          ),
          Expanded(flex: 2, child:TextField(
            controller: _editingControllerQuestion, maxLength: 128,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.question_mark),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(
                  width: 1,
                  style: BorderStyle.solid,
                ),
              ),
              suffixIcon: Container(
                margin: EdgeInsets.all(10),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.0),
                    ),
                  ),
                  onPressed: _isSending ? null : () async {
                    setState(() {
                      _isSending = true;
                      _editingController.text = "";
                    });

                    String myQuery = _editingControllerQuestion.text;
                    final prompt = TextPart("$_selectedCategory query: $myQuery");
                    List<Part> parts = [];
                    parts.add(prompt);

                    // context based parts
                    if(_selectedCategory == 'Flight plan') {
                      List<Destination> destinations = Storage().route.getAllDestinations();
                      if(destinations.isNotEmpty) {
                        final flightPlanPart = TextPart(Storage().route.toString());
                        parts.add(flightPlanPart);
                        String? winds = WindsCache.getWindsAtAll(destinations[0].coordinate, 6);
                        if(winds != null) {
                          final windsPart = TextPart("Use winds:\n $winds");
                          parts.add(windsPart);
                        }
                      }
                      final List<Aircraft> aircraft = await UserDatabaseHelper.db.getAllAircraft();
                      if(aircraft.isNotEmpty) {
                        final aircraft1 = aircraft.first;
                        final aircraftPart = TextPart("Use aircraft:\n ${jsonEncode(aircraft1.toMap())}");
                        parts.add(aircraftPart);
                      }
                    }
                    else if(_selectedCategory == 'Log book') {
                      final filePart = FileData("text/plain", BackupScreen.getUserDataJsonPath());
                      parts.add(filePart);
                    }
                    else if(_selectedCategory == 'Tracks') {
                      final filePart = FileData("text/plain", BackupScreen.getUserTracksPath());
                      parts.add(filePart);
                    }
                    else if(_selectedCategory == 'FAA') {
                    }
                    else if(_selectedCategory == 'Aircraft') {
                      final filePart = FileData("application/pdf", BackupScreen.getAircraftPath());
                      parts.add(filePart);
                    }
                    final query =  Content.multi(parts);
                    final response = await _model.generateContent([query]);
                    setState(() {
                      _isSending = false;
                      if(response.text == null) {
                        _editingController.text = "Error: no response from AI";
                        return;
                      }
                      else {
                        _editingController.text = response.text!;
                      }
                    });
                  },
                  child:Text("Ask"))
              )
            )
          )),
          Expanded(flex: 10, child: TextField(
            controller: _editingController,
            enableInteractiveSelection: true,
            maxLines: null,
            decoration: InputDecoration(
              label: const Text("Answer"),
              border: OutlineInputBorder(),
            ),
          )),
        ],
      ),
    ));
  }
}



