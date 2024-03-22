
import 'package:avaremp/storage.dart';
import 'package:avaremp/twilight_calculator.dart';
import 'package:day_night_time_picker/lib/daynight_timepicker.dart';
import 'package:day_night_time_picker/lib/state/time.dart';
import 'package:flutter/material.dart';

class PlanFileWidget extends StatefulWidget {
  const PlanFileWidget({super.key});


  @override
  State<StatefulWidget> createState() => PlanFileWidgetState();
}


class PlanFileWidgetState extends State<PlanFileWidget> {

  String _aircraftId = "";
  String _aircraftType = "";
  String _flightRule = "";
  String _flightType = "";
  String _numberAircraft = "";
  String _wakeTurbulence = "";
  String _departure = "";
  DateTime _departureDateTime = DateTime.now();

  @override
  Widget build(BuildContext context) {

    DateTime? sunset;
    DateTime? sunrise;
    int state;
    (sunrise, sunset, state) = TwilightCalculator.calculateTwilight(Storage().position.latitude, Storage().position.longitude);

    return Container(
      child: Column(
        children: [
          const Flexible(flex: 1, child: Text("LMFS Flight Plan Filing", style: TextStyle(fontWeight: FontWeight.w800),)),
          const Padding(padding: EdgeInsets.all(10)),
          Row(children: [
          TextButton(
            onPressed: () {
            },
            child: const Text("Send to FAA"),),
          ]),

          Flexible(flex: 5, child:  GridView.count(
              primary: false,
              crossAxisSpacing: 10,
              shrinkWrap: true,
              crossAxisCount: 2,
              childAspectRatio: 3,
              children: <Widget>[
                TextFormField(
                    onChanged: (value) {
                      setState(() {
                        _aircraftId = value;
                      });
                    },
                    initialValue: _aircraftId,
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Aircraft ID')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                        _aircraftType = value;
                      });
                    },
                    initialValue: _aircraftType,
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Aircraft Type')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                        _flightRule = value;
                      });
                    },
                    controller: TextEditingController()..text = _flightRule,
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Flight Rule')
                ),

                Container(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(children: [
                  TextButton(child: const Text("VFR"), onPressed: () {
                    setState(() {
                      _flightRule = "VFR";
                    });
                  },),
                  TextButton(child: const Text("IFR"), onPressed: () {
                    setState(() {
                      _flightRule = "IFR";
                    });
                  },),
                ]))),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                        _flightType = value;
                      });
                    },
                    controller: TextEditingController()..text = _flightType,
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Flight Type')
                ),

                Container(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                  TextButton(child: const Text("General Aviation"), onPressed: () {
                    setState(() {
                      _flightType = "General Aviation";
                    });
                  },),
                  TextButton(child: const Text("Scheduled"), onPressed: () {
                    setState(() {
                      _flightType = "Scheduled";
                    });
                  },),
                  TextButton(child: const Text("Non Scheduled"), onPressed: () {
                    setState(() {
                      _flightType = "Non Scheduled";
                    });
                  },),
                  TextButton(child: const Text("Military"), onPressed: () {
                    setState(() {
                      _flightType = "Military";
                    });
                  },),
                  TextButton(child: const Text("Other"), onPressed: () {
                    setState(() {
                      _flightType = "Other";
                    });
                  },),
                ]))),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                        _numberAircraft = value;
                      });
                    },
                    controller: TextEditingController()..text = _numberAircraft,
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Number of Aircraft')
                ),

                Row(children: [TextButton(child: const Text("1"), onPressed: () {
                  setState(() {
                    _numberAircraft = "1";
                  });
                },),]),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    controller: TextEditingController()..text = _wakeTurbulence,
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Wake Turbulence')
                ),

                Container(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                  TextButton(child: const Text("LIGHT"), onPressed: () {
                    setState(() {
                      _wakeTurbulence = "LIGHT";
                    });
                  },),
                  TextButton(child: const Text("MEDIUM"), onPressed: () {
                    setState(() {
                      _wakeTurbulence = "MEDIUM";
                    });
                  },),
                  TextButton(child: const Text("HEAVY"), onPressed: () {
                    setState(() {
                      _wakeTurbulence = "HEAVY";
                    });
                  },),
                ]))),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Aircraft Equipment')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                        _departure = value;
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Departure')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                        _departureDateTime = DateTime.parse(value);
                      });
                    },
                    controller: TextEditingController()..text = _departureDateTime.toUtc().toString().substring(0, 16),
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Departure Date/Time')
                ),

                Container(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children:[
                  TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      showPicker(
                        context: context,
                        okText: "OK",
                        cancelText: "CANCEL",
                        value: Time(hour: DateTime.now().hour, minute: DateTime.now().minute),
                        sunrise: sunrise == null ? const TimeOfDay(hour: 6, minute: 0) : TimeOfDay(hour: sunrise.hour, minute: sunrise.minute),
                        sunset: sunset == null ? const TimeOfDay(hour: 18, minute: 0) : TimeOfDay(hour: sunset.hour, minute: sunset.minute),
                        duskSpanInMinutes: 15,
                        onChange: (value) {
                          setState(() {
                            _departureDateTime = _departureDateTime.copyWith(hour: value.hour, minute: value.minute);
                          });
                        },
                      ),
                    );
                  },
                  child: const Text("Time"),),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        _departureDateTime = _departureDateTime.add(const Duration(days: 1));
                      });
                    },
                    child: const Text("+1 Day")),

                  TextButton(
                      onPressed: () {
                        setState(() {
                          _departureDateTime = _departureDateTime.subtract(const Duration(days: 1));
                        });
                      },
                      child: const Text("-1 Day")),
                ]))),


                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Cruising Speed')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Altitude')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Route')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Other Information')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Destination')
                ),

                Container(),


                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Total Elpased Time')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Alternate Airport 1')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Alternate Airport 2')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Fuel Endurance')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'People On Board')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Aircraft Color')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Remarks')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Pilot in Command')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Pilot Information')
                ),

                Container(),

                TextFormField(
                    onChanged: (value) {
                      setState(() {
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Surveillance Equipment')
                ),

              ],
            ),
          )
        ],
      )
    );
  }
}

