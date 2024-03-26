import 'package:avaremp/plan_file_widget.dart';
import 'package:avaremp/plan_lmfs.dart';
import 'package:flutter/material.dart';

import 'package:avaremp/storage.dart';
import 'package:avaremp/twilight_calculator.dart';
import 'package:day_night_time_picker/lib/daynight_timepicker.dart';
import 'package:day_night_time_picker/lib/state/time.dart';

class PlanManageWidget extends StatefulWidget {
  const PlanManageWidget({super.key});


  @override
  State<StatefulWidget> createState() => PlanManageWidgetState();
}

class PlanManageWidgetState extends State<PlanManageWidget> {

  bool _sending = false;
  String _error = "Using 1800wxbrief.com account '${Storage().settings.getEmail()}'";
  Color _errorColor = Colors.white;

  Future<LmfsPlanList> getPlans() async {
    LmfsPlanList ret;
    LmfsInterface interface = LmfsInterface();
    ret = await interface.getFlightPlans();
    return ret;
  }

  Widget _makeContent(LmfsPlanList? plans) {

    if(null == plans) {
      return const Column(
          children: [
            Flexible(flex: 1, child: Text("Manage FAA Plans", style: TextStyle(fontWeight: FontWeight.w800),)),
            Padding(padding: EdgeInsets.all(10)),
            CircularProgressIndicator()
          ]
      );
    }

    List<LmfsPlanListPlan> items = plans.getPlans();
    DateTime? sunset;
    DateTime? sunrise;
    (sunrise, sunset) = TwilightCalculator.calculateTwilight(Storage().position.latitude, Storage().position.longitude);

    return Column(
        children: [
          const Flexible(flex: 1, child: Text("Manage FAA Plans", style: TextStyle(fontWeight: FontWeight.w800),)),
          const Padding(padding: EdgeInsets.all(10)),
          Flexible(flex: 5, child: ListView.separated(
            itemCount: items.length,
            padding: const EdgeInsets.all(5),
            itemBuilder: (context, index) {
              final LmfsPlanListPlan item = items[index];
              return ListTile(
                title: Text("${item.departure} -> ${item.destination} (${item.aircraftId})"),
                leading: Column(
                    children:[
                      // can cancel in proposed state
                      if(item.currentState != "ACTIVE")
                        TextButton(
                          onPressed: () {
                            LmfsInterface interface = LmfsInterface();
                            setState(() {
                              _sending = true;
                              _error = "";
                            });
                            interface.cancelFlightPlan(item.id).then((value) => setState(() {
                              _error = interface.error;
                              if(_error.isNotEmpty) {
                                _errorColor = Colors.red;
                              }
                              _sending = false;
                            }));
                          },
                          child: const Text("Cancel"),),
                    ]),
                subtitle: Row(children:[
                  Text(item.currentState),
                  const Padding(padding: EdgeInsets.fromLTRB(10, 0, 0, 0)),
                  Visibility(visible: _sending, child: const CircularProgressIndicator(),),
                  const Padding(padding: EdgeInsets.fromLTRB(10, 0, 0, 0)),
                  // Show an error and a question mark with error code when error, otherwise show a check mark
                  Tooltip(message: _error, child: _sending ?
                  Container() : _error.isEmpty ?
                  const Icon(Icons.check, color: Colors.green,) :
                  Icon(Icons.question_mark, color: _errorColor,)),
                ]),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children : [
                    if(item.currentState == "ACTIVE")
                      TextButton(
                        onPressed: () {
                            LmfsInterface interface = LmfsInterface();
                            setState(() {
                              _sending = true;
                              _error = "";
                            });
                            interface.closeFlightPlan(item.id).then((value) => setState(() {
                              _error = interface.error;
                              if(_error.isNotEmpty) {
                                _errorColor = Colors.red;
                              }
                              _sending = false;

                            }));
                        },
                        child: const Text("Close"),),
                    if(item.currentState == "PROPOSED")
                      // can activate in proposed state
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            showPicker(
                              context: context,
                              okText: "ACTIVATE",
                              cancelText: "CANCEL",
                              value: Time(hour: DateTime.now().hour, minute: DateTime.now().minute),
                              sunrise: sunrise == null ? const TimeOfDay(hour: 6, minute: 0) : TimeOfDay(hour: sunrise.hour, minute: sunrise.minute),
                              sunset: sunset == null ? const TimeOfDay(hour: 18, minute: 0) : TimeOfDay(hour: sunset.hour, minute: sunset.minute),
                              duskSpanInMinutes: 15,
                              onChange: (value) {
                                DateTime depart = DateTime.now().copyWith(hour: value.hour, minute: value.minute);
                                LmfsInterface interface = LmfsInterface();
                                setState(() {
                                  _sending = true;
                                  _error = "";
                                });
                                interface.activateFlightPlan(item.id, item.versionStamp,
                                    PlanFileWidgetState.stringTime(depart)).then((value) => setState(() {
                                  _error = interface.error;
                                  if(_error.isNotEmpty) {
                                    _errorColor = Colors.red;
                                  }
                                  _sending = false;

                                }));
                              },
                            ),
                          );
                        },
                        child: const Text("Depart"),),
                  ],),
              );
            },
            separatorBuilder: (context, index) {
              return const Divider();
            },
          ))
        ]);
  }


  @override
  Widget build(BuildContext context) {

    // get all aircraft since it is important to be able to change them quickly
    return FutureBuilder(
        future: getPlans(),
        builder: (context, snapshot) {
          return _makeContent(snapshot.data);
        });
  }

}

