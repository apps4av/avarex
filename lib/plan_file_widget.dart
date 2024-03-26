
import 'package:avaremp/plan_lmfs.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/twilight_calculator.dart';
import 'package:day_night_time_picker/lib/daynight_timepicker.dart';
import 'package:day_night_time_picker/lib/state/time.dart';
import 'package:flutter/material.dart';

import 'aircraft.dart';
import 'constants.dart';
import 'data/user_database_helper.dart';
import 'destination.dart';

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
  String _aircraftEquipment = "S";
  String _departure = "";
  DateTime _departureDateTime = DateTime.now();
  String _destination = "";
  Duration _elapsedTime = const Duration(minutes: 0);
  String _route = "";
  String _cruisingSpeed = "";
  String _altitude = "";
  String _surveillanceEquipment = "N";
  String _otherInformation = "";
  String _alternate1 = "";
  String _alternate2 = "";
  String _peopleOnBoard = "";
  String _pilotInformation = "";
  Duration _fuelEndurance = const Duration(minutes: 0);
  String _aircraftColor = "";
  String _pilotInCommand = "";
  String _remarks = "";
  List<Aircraft>? _aircraft;

  bool _sending = false;
  String _error = "Using 1800wxbrief.com account '${Storage().settings.getEmail()}'";
  Color _errorColor = Colors.white;
  
  @override
  Widget build(BuildContext context) {

    // get all aircraft since it is important to be able to change them quickly
    return FutureBuilder(
        future: UserDatabaseHelper.db.getAllAircraft(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            _aircraft = snapshot.data;
          }
          return _makeContent(_aircraft);
        });
  }

  PlanLmfs _makeLmfs() {
    PlanLmfs lmfs = PlanLmfs();
    lmfs.aircraftId = _aircraftId;
    lmfs.flightRule = _flightRule;
    lmfs.flightType = _flightType;
    lmfs.noOfAircraft = _numberAircraft;
    lmfs.aircraftType = _aircraftType;
    lmfs.wakeTurbulence = _wakeTurbulence;
    lmfs.aircraftEquipment = _aircraftEquipment;
    lmfs.departure = _departure;
    lmfs.departureDate = stringTime(_departureDateTime);
    lmfs.cruisingSpeed = _cruisingSpeed;
    lmfs.level = _altitude;
    lmfs.surveillanceEquipment = _surveillanceEquipment;
    lmfs.route = _route;
    lmfs.otherInfo = _otherInformation;
    lmfs.destination = _destination;
    lmfs.totalElapsedTime = "${_elapsedTime.inHours}H${_elapsedTime.inMinutes % 60}M";
    lmfs.alternate1 = _alternate1;
    lmfs.alternate2 = _alternate2;
    lmfs.fuelEndurance = "${_fuelEndurance.inHours}H${_fuelEndurance.inMinutes % 60}M";
    lmfs.peopleOnBoard = _peopleOnBoard;
    lmfs.aircraftColor = _aircraftColor;
    lmfs.supplementalRemarks = _remarks;
    lmfs.pilotInCommand = _pilotInCommand;
    lmfs.pilotInfo = _pilotInformation;
    return lmfs;
  }

  static String stringTime(DateTime time) {
    return time.toUtc().toString().substring(0, 16);
  }

  Widget _makeContent(List<Aircraft>? aircraft) {

    if(null == aircraft) {
      return Container();
    }

    String k = Constants.useK ? "K" : "";
    PlanRoute route = Storage().route;
    int length = route.length;

    // this is for time picker to show day/night
    DateTime? sunset;
    DateTime? sunrise;
    (sunrise, sunset) = TwilightCalculator.calculateTwilight(Storage().position.latitude, Storage().position.longitude);

    return Column(
      children: [
        const Flexible(flex: 1, child: Text("Send Plan to FAA", style: TextStyle(fontWeight: FontWeight.w800),)),

        const Padding(padding: EdgeInsets.all(10)),

        Flexible(flex: 8, child:  GridView.count(
            primary: false,
            crossAxisSpacing: 10,
            shrinkWrap: true,
            crossAxisCount: 2,
            childAspectRatio: 3,
            children: <Widget>[
              TextFormField(
                  onChanged: (value) {
                    _aircraftId = value;
                  },
                  controller: TextEditingController()..text = _aircraftId,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Aircraft ID')
              ),

              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                for(Aircraft a in aircraft)
                  TextButton(child: Text(a.tail), onPressed: () {
                    setState(() {
                      _aircraftId = a.tail;
                      _aircraftType = a.type;
                      _aircraftEquipment = a.equipment;
                      _surveillanceEquipment = a.surveillance;
                      _wakeTurbulence = a.wake;
                      try {
                        _fuelEndurance = Duration(
                            minutes: (double.parse(a.fuelEndurance) * 60)
                                .toInt());
                      }
                      catch(e) {
                        _fuelEndurance = const Duration(hours: 0);
                      }
                      _pilotInCommand = a.pic;
                      _pilotInformation = a.picInfo;
                      _aircraftColor = a.color;
                    });
                  },),
              ])),

              TextFormField(
                  onChanged: (value) {
                    _aircraftType = value;
                  },
                  controller: TextEditingController()..text =  _aircraftType,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Aircraft Type')
              ),

              Container(),

              TextFormField(
                  onChanged: (value) {
                    _flightRule = value;
                  },
                  controller: TextEditingController()..text = _flightRule,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Flight Rule')
              ),

              SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(children: [
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
              ])),

              TextFormField(
                  onChanged: (value) {
                    _flightType = value;
                  },
                  controller: TextEditingController()..text = _flightType,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Flight Type')
              ),

              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                TextButton(child: const Text("General Aviation"), onPressed: () {
                  setState(() {
                    _flightType = "G";
                  });
                },),
                TextButton(child: const Text("Scheduled"), onPressed: () {
                  setState(() {
                    _flightType = "S";
                  });
                },),
                TextButton(child: const Text("Non Scheduled"), onPressed: () {
                  setState(() {
                    _flightType = "N";
                  });
                },),
                TextButton(child: const Text("Military"), onPressed: () {
                  setState(() {
                    _flightType = "M";
                  });
                },),
                TextButton(child: const Text("Other"), onPressed: () {
                  setState(() {
                    _flightType = "O";
                  });
                },),
              ])),

              TextFormField(
                  onChanged: (value) {
                    _numberAircraft = value;
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
                  },
                  controller: TextEditingController()..text = _wakeTurbulence,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Wake Turbulence')
              ),

              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
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
              ])),

              TextFormField(
                  onChanged: (value) {
                    _aircraftEquipment = value;
                  },
                  controller: TextEditingController()..text = _aircraftEquipment,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Aircraft Equipment')
              ),

              Row(children:[TextButton(child: Text(_aircraftEquipment), onPressed: () {
                setState(() {
                  _aircraftEquipment = "S";
                });
              },)]),

              TextFormField(
                onChanged: (value) {
                  _departure = value;
                },
                controller: TextEditingController()..text = _departure,
                decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Departure')
              ),

              Row(children:[TextButton(child: const Text("Planned"), onPressed: () {
                setState(() {
                  if(length > 0) {
                    Destination departure = route.getWaypointAt(0).destination;
                    if (departure is AirportDestination) {
                      _departure = "$k${departure.locationID}";
                    }
                  }
                });
              },)]),

              TextFormField(
                  onChanged: (value) {
                    try {
                      _departureDateTime = DateTime.parse(value);
                    }
                    catch(e) {}
                  },
                  controller: TextEditingController()..text = stringTime(_departureDateTime),
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Departure Date/Time')
              ),

              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children:[
                TextButton(
                    onPressed: () {
                      setState(() {
                        _departureDateTime = DateTime.now();
                      });
                    },
                    child: const Text("Now")),

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
              ])),

              TextFormField(
                  onChanged: (value) {
                    _cruisingSpeed = value;
                  },
                  controller: TextEditingController()..text = _cruisingSpeed,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Cruising Speed')
              ),

              Row(children:[TextButton(child: Text(Storage().settings.getTas().toString()), onPressed: () {
                setState(() {
                  _cruisingSpeed = Storage().settings.getTas().toString();
                });
              },)]),

              TextFormField(
                  onChanged: (value) {
                    _altitude = value;
                  },
                  controller: TextEditingController()..text = _altitude,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Altitude')
              ),

              Row(children:[
                TextButton(child: Text((int.parse(route.altitude) ~/ 100).toString().padLeft(3, "0")),
                  onPressed: () {
                    setState(() {
                      _altitude = (int.parse(route.altitude) ~/ 100).toString().padLeft(3, "0");
                    });
                },)
              ]),

              TextFormField(
                  onChanged: (value) {
                    _surveillanceEquipment = value;
                  },
                  controller: TextEditingController()..text = _surveillanceEquipment,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Surveillance Equipment')
              ),

              Row(children:[TextButton(child: Text(_surveillanceEquipment), onPressed: () {
                setState(() {
                  _surveillanceEquipment = "N";
                });
              },)]),

              TextFormField(
                  onChanged: (value) {
                    _route = value;
                  },
                  controller: TextEditingController()..text = _route,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Route')
              ),

              SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: Row(children:[TextButton(child: const Text("Planned"), onPressed: () {
                setState(() {
                  if(length > 2) {
                    _route = "";
                    for(int waypoint = 1; waypoint < length - 1; waypoint++) {
                      _route = "$_route ${route.getWaypointAt(waypoint).destination.toString()}";
                    }
                  }
                  else {
                    _route = "DCT";
                  }
                });
              },)])),

              TextFormField(
                  onChanged: (value) {
                    _otherInformation = value;
                  },
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Other Information')
              ),

              Container(),

              TextFormField(
                  onChanged: (value) {
                    _destination = value;
                  },
                  controller: TextEditingController()..text = _destination,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Destination')
              ),

              Row(children:[TextButton(child: const Text("Planned"), onPressed: () {
                setState(() {
                  if(length > 1) {
                    Destination destination = route.getWaypointAt(length - 1).destination;
                    if (destination is AirportDestination) {
                      _destination = "$k${destination.locationID}";
                    }
                  }
                });
              },)]),

              TextFormField(
                  onChanged: (value) {
                    RegExp exp = RegExp(r"(\d*)H(\d*)M");
                    RegExpMatch? match = exp.firstMatch(value);
                    if(null != match && null != match.group(1) && null != match.group(2)) {
                      try {
                        _elapsedTime = Duration(
                            hours: int.parse(match.group(1)!),
                            minutes: int.parse(match.group(2)!));
                      }
                      catch(e) {}
                    }
                  },
                  controller: TextEditingController()..text = "${_elapsedTime.inHours}H${_elapsedTime.inMinutes % 60}M",
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Total Elapsed Time')
              ),

              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children:[

                TextButton(
                  onPressed: () {
                    setState(() {
                      if(route.totalCalculations != null) {
                        int time = route.totalCalculations!.time.toInt();
                        _elapsedTime = Duration(seconds: time);
                      }
                    });
                  },
                  child: const Text("Planned")),

                TextButton(
                  onPressed: () {
                    setState(() {
                      _elapsedTime = Duration(minutes: _elapsedTime.inMinutes + 1);
                    });
                  },
                  child: const Text("+1M")),

                TextButton(
                    onPressed: () {
                      setState(() {
                        _elapsedTime = Duration(minutes: _elapsedTime.inMinutes + 15);
                      });
                    },
                    child: const Text("+15M")),

              ])),

              TextFormField(
                  onChanged: (value) {
                    _alternate1 = value;
                  },
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Alternate Airport 1')
              ),

              Container(),

              TextFormField(
                  onChanged: (value) {
                    _alternate2 = value;
                  },
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Alternate Airport 2')
              ),

              Container(),

              TextFormField(
                  onChanged: (value) {
                    RegExp exp = RegExp(r"(\d*)H(\d*)M");
                    RegExpMatch? match = exp.firstMatch(value);
                    if(null != match && null != match.group(1) && null != match.group(2)) {
                      try {
                        _fuelEndurance = Duration(
                            hours: int.parse(match.group(1)!),
                            minutes: int.parse(match.group(2)!));
                      }
                      catch(e) {}
                    }
                  },
                  controller: TextEditingController()..text = "${_fuelEndurance.inHours}H${_fuelEndurance.inMinutes % 60}M",
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Fuel Endurance')
              ),


              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children:[

                TextButton(
                    onPressed: () {
                      setState(() {
                        _fuelEndurance = Duration(minutes: _fuelEndurance.inMinutes - 15);
                      });
                    },
                    child: const Text("-15M")),

                TextButton(
                    onPressed: () {
                      setState(() {
                        _fuelEndurance = Duration(minutes: _fuelEndurance.inMinutes + 15);
                      });
                    },
                    child: const Text("+15M")),

              ])),


              TextFormField(
                  onChanged: (value) {
                    _peopleOnBoard = value;
                  },
                  controller: TextEditingController()..text = _peopleOnBoard,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'People On Board')
              ),

              SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(children: [
                TextButton(child: const Text("1"), onPressed: () {
                  setState(() {
                    _peopleOnBoard = "1";
                  });
                },),
                TextButton(child: const Text("2"), onPressed: () {
                  setState(() {
                    _peopleOnBoard = "2";
                  });
                },),
                TextButton(child: const Text("3"), onPressed: () {
                  setState(() {
                    _peopleOnBoard = "3";
                  });
                },),
                TextButton(child: const Text("4"), onPressed: () {
                  setState(() {
                    _peopleOnBoard = "4";
                  });
                },),
              ])),

              TextFormField(
                  onChanged: (value) {
                    _aircraftColor = value;
                  },
                  controller: TextEditingController()..text = _aircraftColor,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Aircraft Color')
              ),

              Container(),

              TextFormField(
                  onChanged: (value) {
                    _remarks = value;
                  },
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Remarks')
              ),

              Container(),

              TextFormField(
                  onChanged: (value) {
                    _pilotInCommand = value;
                  },
                  controller: TextEditingController()..text = _pilotInCommand,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Pilot in Command')
              ),

              Container(),

              TextFormField(
                  onChanged: (value) {
                    _pilotInformation = value;
                  },
                  controller: TextEditingController()..text = _pilotInformation,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Pilot Information')
              ),

              Container(),
            ],
          ),
        ),

        const Padding(padding: EdgeInsets.all(10)),

        Flexible(flex: 1, child: Row(children: [
          TextButton(
            onPressed: () {
              PlanLmfs lmfs = _makeLmfs();
              LmfsInterface interface = LmfsInterface();
              setState(() {
                _sending = true;
                _error = "";
              });
              interface.getBriefing(lmfs).then((value) {
                setState(() {
                  _error = interface.error;
                  if(_error.isNotEmpty) {
                    _errorColor = Colors.red;
                  }
                  _sending = false;
                });
              });
            },
            child: const Text("Get Email Brief"),),
          TextButton(
            onPressed: () {
              PlanLmfs lmfs = _makeLmfs();
              LmfsInterface interface = LmfsInterface();
              setState(() {
                _sending = true;
                _error = "";
              });
              interface.fileFlightPlan(lmfs).then((value) {
                setState(() {
                  _error = interface.error;
                  if(_error.isNotEmpty) {
                    _errorColor = Colors.red;
                  }
                  _sending = false;
                });
              });
            },
            child: const Text("Send to FAA"),),
          const Padding(padding: EdgeInsets.fromLTRB(10, 0, 0, 0)),
          Visibility(visible: _sending, child: const CircularProgressIndicator(),),
          const Padding(padding: EdgeInsets.fromLTRB(10, 0, 0, 0)),
          // Show an error and a question mark with error code when error, otherwise show a check mark
          Tooltip(message: _error, child: _sending ?
          Container() : _error.isEmpty ?
          const Icon(Icons.check, color: Colors.green,) :
          Icon(Icons.question_mark, color: _errorColor,)),
        ])),
      ],
    );
  }
}

