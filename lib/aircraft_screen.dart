import 'package:avaremp/aircraft.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'constants.dart';

class AircraftScreen extends StatefulWidget {
  const AircraftScreen({super.key});
  @override
  AircraftScreenState createState() => AircraftScreenState();
}

class AircraftScreenState extends State<AircraftScreen> {

  String? _selected;

  Widget _makeContent(List<Aircraft>? items) {

    String inStorage = Storage().settings.getAircraft();

    if(null != items && items.isNotEmpty) {
      _selected = items[0].tail; // use first item if nothing in storage
      for (Aircraft a in items) {
        if (a.tail == inStorage) { // found the airplane
          _selected = a.tail;
        }
      }
    }

    return Scaffold(
        appBar: AppBar(
            backgroundColor: Constants.appBarBackgroundColor,
            title: const Text("Aircraft"),
            actions: _makeAction(items)
        ),
        body: _makeBody(items)
    );
  }

  List<Widget> _makeAction(List<Aircraft>? items) {
    if(null == items || items.isEmpty) {
      return [];
    }
    return [Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        child: DropdownButtonHideUnderline(
            child: DropdownButton2<String>( // airport selection
              buttonStyleData: ButtonStyleData(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Constants.dropDownButtonBackgroundColor),
              ),
              dropdownStyleData: DropdownStyleData(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
              ),
              isExpanded: false,
              value: _selected,
              items: items.map((Aircraft e) => DropdownMenuItem<String>(value: e.tail, child: Text(e.tail, style: TextStyle(fontSize: Constants.dropDownButtonFontSize)))).toList(),
              onChanged: (value) {
                setState(() {
                  _selected = value;
                  Storage().settings.setAircraft(value!);
                });
              },
            )
        )
    )];
  }

  Widget _makeBody(List<Aircraft>? items) {

    Aircraft active = Aircraft.empty();
    if(null != _selected && null != items) {
      for (Aircraft a in items) {
        if (a.tail == _selected) {
          active = a;
        }
      }
    }

    // has a set of value and help
    List<_Entry> entries = [];
    entries.add(_Entry("Tail Number",                               "tail",           active.tail,           const Tooltip(message: "Tail number, for example, N172EF.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Type",                                      "type",           active.type,           const Tooltip(message: "Type, for example, C172.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Color & Markings",                          "color",          active.color,          const Tooltip(message: "Use a combination of the following colors, for example, for white and blue, enter W/B.\nA  = Amber\nB  = Blue\nBE = Beige\nBK = Black\nBR = Brown\nG  = Green\nGD = Gold\nGY = Gray\nM  = Maroon\nO  = Orange\nOD = Olive Drab\nP  = Purple\nPK = Pink\nR  = Red\nS  = Silver\nTQ = Turquoise\nT  = Tan\nV  = Violet\nW  = White\nY  = Yellow\n", child: Icon(Icons.question_mark))));
    entries.add(_Entry("PIC",                                       "pic",            active.pic,            const Tooltip(message: "Name of the pilot, for example, John Smith.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("PIC Information",                           "picInfo",        active.picInfo,        const Tooltip(message: "Pilot information, for example, phone number.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Home Base",                                 "base",           active.base,           const Tooltip(message: "Where the aircraft is based at, for example, KBVY.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Mode S Code",                               "icao",           active.icao,           const Tooltip(message: "Mode S code in base 16 / hex (registry.faa.gov), for example A12105.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Cruise Speed",                              "cruiseTas",      active.cruiseTas,      const Tooltip(message: "Airspeed in cruise in unit Knots, for example, 110.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Fuel Endurance",                            "fuelEndurance",  active.fuelEndurance,  const Tooltip(message: "Fuel endurance in hours, for example, for 5 hours 30 minutes enter 5.5.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Fuel Burn Rate",                            "fuelBurn",       active.fuelBurn,       const Tooltip(message: "Fuel burn rate in unit per hour, for example, for 10 gallons per hour, enter 10.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Sink Rate",                                 "sinkRate",       active.sinkRate,       const Tooltip(message: "Sink rate in unit feet per minute, for example, 700.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Wake Turbulence",                           "wake",           active.wake,           const Tooltip(message: "Wake turbulence category, enter one of LIGHT, MEDIUM, or HEAVY.", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Navigation, Communications, Approach Aid",  "equipment",      active.equipment,      const Tooltip(message: "A: GBAS landing system\nB: LPV (APCH with SBAS)\nC: LORAN C\nD: DME (Distance Measuring Equipment)\nG: GNSS (Global Navigation Satellite System)\nI: INS (Inertial Navigation System)\nL: ILS (Instrument Landing System)\nO: VOR (VHF Omnidirectional Range)\nR: PBN approved (Performance-Based Navigation)\nS: Standard equipment (ILS, VOR, VHF Comm)\nT: TACAN\nV: VHF Comm\nU: UHF\nW: RVSM (Reduced Vertical Separation Minimum)", child: Icon(Icons.question_mark))));
    entries.add(_Entry("Surveillance",                              "surveillance",   active.surveillance,   const Tooltip(message: "N: No capabilities\nA: Mode A (no Mode C)\nC: Modes A and C\nS: Mode S- ACID and Altitude\nP: Mode S- Altitude, no ACID\nI: Mode S- ACID, no Altitude\nX: Mode S- no ACID, no Altitude\nE: Mode S- ACID, Altitude, Extended Squitter\nH: Mode S- ACID, Altitude, Enhanced Surveillance\nL: Mode S- ACID, Altitude, Enhanced Surveillance\nB1: 1090 MHz “out”\nB2: 1090 MHz “out” and “in”\nU1: UAT “out”\nU2: UAT “out” and “in”\nV1: VDL Mode 4 “out”\nV2: VDL Mode 4 “out” and “in”\nD1: ADS-C FANS 1/A\nG1: ADS-C ATN", child: Icon(Icons.question_mark))));


    return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              for(_Entry e in entries)
                Row(children: [
                  Flexible(flex: 4, child: TextFormField(
                      onChanged: (value) {
                        e.value = value;
                      },
                      controller: TextEditingController()..text = e.value,
                      decoration: InputDecoration(border: const UnderlineInputBorder(), labelText: e.name)
                  )),
                  Flexible(flex: 1, child: e.widget),
                ]),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  TextButton(
                      onPressed: () {
                        String? entry = _selected;
                        if(null != entry) {
                          UserDatabaseHelper.db.deleteAircraft(entry);
                        }
                        Storage().settings.setAircraft("");
                        setState(() {
                          _selected = null;
                        });
                      },
                      child: const Text("Delete")
                  ),
                  TextButton(
                    onPressed: () {
                      // take all of whats here and save
                      Map<String, dynamic> mm = { for (var v in entries) v.map : v.value };
                      Aircraft a = Aircraft.fromMap(mm);
                      UserDatabaseHelper.db.addAircraft(a).then((value) => setState(() {
                        Storage().settings.setAircraft(a.tail);
                      }));
                    },
                    child: const Text("Save")
                  ),
                ]))
            ],
          )
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: UserDatabaseHelper.db.getAllAircraft(),
        builder: (context, snapshot) {
          List<Aircraft>? data = snapshot.data;
          if (snapshot.connectionState == ConnectionState.done && data != null) {
          }
          return _makeContent(data);
        }
    );
  }
}

class _Entry {

  String name;
  String map;
  String value;
  Widget widget;

  _Entry(this.name, this.map, this.value, this.widget);

}

