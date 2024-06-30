import 'package:avaremp/aircraft.dart';
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
    return [
      Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
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
    entries.add(_Entry("Tail Number",                               "tail",           active.tail,           const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Tail number, for example, N172EF.", child: Icon(Icons.info))));
    entries.add(_Entry("Type",                                      "type",           active.type,           const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Type, for example, C172.", child: Icon(Icons.info))));
    entries.add(_Entry("Color & Markings",                          "color",          active.color,          const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Use a combination of the following colors, for example, for white and blue, enter W/B.\nA  = Amber\nB  = Blue\nBE = Beige\nBK = Black\nBR = Brown\nG  = Green\nGD = Gold\nGY = Gray\nM  = Maroon\nO  = Orange\nOD = Olive Drab\nP  = Purple\nPK = Pink\nR  = Red\nS  = Silver\nTQ = Turquoise\nT  = Tan\nV  = Violet\nW  = White\nY  = Yellow\n", child: Icon(Icons.info))));
    entries.add(_Entry("PIC",                                       "pic",            active.pic,            const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Name of the pilot, for example, John Smith.", child: Icon(Icons.info))));
    entries.add(_Entry("PIC Information",                           "picInfo",        active.picInfo,        const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Pilot information, for example, phone number.", child: Icon(Icons.info))));
    entries.add(_Entry("Home Base",                                 "base",           active.base,           const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Where the aircraft is based at, for example, KBVY.", child: Icon(Icons.info))));
    entries.add(_Entry("Mode S Code",                               "icao",           active.icao,           const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Mode S code in base 16 / hex (registry.faa.gov), for example A12105.", child: Icon(Icons.info))));
    entries.add(_Entry("Cruise Speed",                              "cruiseTas",      active.cruiseTas,      const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Airspeed in cruise in unit Knots, for example, 110.", child: Icon(Icons.info))));
    entries.add(_Entry("Fuel Endurance",                            "fuelEndurance",  active.fuelEndurance,  const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Fuel endurance in hours, for example, for 5 hours 30 minutes enter 5.5.", child: Icon(Icons.info))));
    entries.add(_Entry("Fuel Burn Rate",                            "fuelBurn",       active.fuelBurn,       const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Fuel burn rate in unit per hour, for example, for 10 gallons per hour, enter 10.", child: Icon(Icons.info))));
    entries.add(_Entry("Sink Rate",                                 "sinkRate",       active.sinkRate,       const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Sink rate in unit feet per minute, for example, 700.", child: Icon(Icons.info))));
    entries.add(_Entry("Wake Turbulence",                           "wake",           active.wake,           const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Wake turbulence category, enter one of LIGHT, MEDIUM, or HEAVY.", child: Icon(Icons.info))));
    entries.add(_Entry("Navigation, Communications, Approach Aid",  "equipment",      active.equipment,      const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "A: GBAS landing system\nB: LPV (APCH with SBAS)\nC: LORAN C\nD: DME (Distance Measuring Equipment)\nG: GNSS (Global Navigation Satellite System)\nI: INS (Inertial Navigation System)\nL: ILS (Instrument Landing System)\nO: VOR (VHF Omnidirectional Range)\nR: PBN approved (Performance-Based Navigation)\nS: Standard equipment (ILS, VOR, VHF Comm)\nT: TACAN\nV: VHF Comm\nU: UHF\nW: RVSM (Reduced Vertical Separation Minimum)", child: Icon(Icons.info))));
    entries.add(_Entry("Surveillance",                              "surveillance",   active.surveillance,   const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "N: No capabilities\nA: Mode A (no Mode C)\nC: Modes A and C\nS: Mode S- ACID and Altitude\nP: Mode S- Altitude, no ACID\nI: Mode S- ACID, no Altitude\nX: Mode S- no ACID, no Altitude\nE: Mode S- ACID, Altitude, Extended Squitter\nH: Mode S- ACID, Altitude, Enhanced Surveillance\nL: Mode S- ACID, Altitude, Enhanced Surveillance\nB1: 1090 MHz “out”\nB2: 1090 MHz “out” and “in”\nU1: UAT “out”\nU2: UAT “out” and “in”\nV1: VDL Mode 4 “out”\nV2: VDL Mode 4 “out” and “in”\nD1: ADS-C FANS 1/A\nG1: ADS-C ATN", child: Icon(Icons.info))));
    entries.add(_Entry("Other Information",                         "other",          active.other,          const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "STS/ Special Handling\nPBN/ Performance Based Navigation\nNAV/ Other Navigation Capability \nCOM/ Other Communications Capability\nDAT/ Other Data Application\nSUR/ Other Surv. Capability\nDEP/ Non-standard Departure (e.g. MD24)\nDEST/ Non-standard Destination\nDOF/ Date of Flight (YYMMDD, e.g. 121123)\nREG/ Registration (e.g. N123A)\nEET/ Estimated Elapsed Times (e.g. KZNY0124)\nSEL/ SELCAL (e.g. BPAM)\nTYP/ Non-standard AC Type\nCODE/ Aircraft/Mode S address in hex (e.g. A519D9)\nDLE/ Delay (at a fix) (e.g. EXXON0120)\nOPR/ Operator, when not evident from ACID\nORGN/ Flight Plan Originator (e.g. KHOUARCW)\nPER/ Performance Category (e.g. A)\nALTN/ Non-standard Alternate(s) (e.g. 61NC)\nRALT/ Enroute Alternate(s) (e.g. EINN CYYR KDTW)\nTALT/ Take-off Alternate(s) (e.g. KTEB)\nRIF/ Route to revised Destination\nRMK/ Remarks", child: Icon(Icons.info))));

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

                    Padding(padding: const EdgeInsets.all(20), child: Dismissible(key: GlobalKey(),
                        background: const Icon(Icons.delete_forever),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) {
                          String? entry = _selected;
                          if(null != entry) {
                            Storage().realmHelper.deleteAircraft(entry);
                          }
                          Storage().settings.setChecklist("");
                          setState(() {
                            _selected = null;
                          });
                        },
                        child: const Column(children:[Icon(Icons.swipe_left), Text("Delete", style: TextStyle(fontSize: 8))])
                    )),

                    TextButton(
                      onPressed: () {
                        // take all of whats here and save
                        Map<String, dynamic> mm = { for (var v in entries) v.map : v.value };
                        Aircraft a = Aircraft.fromMap(mm);
                        Storage().realmHelper.addAircraft(a);
                        setState(() {
                          Storage().settings.setAircraft(a.tail);
                        });
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
    List<Aircraft>? data = Storage().realmHelper.getAllAircraft();
    return _makeContent(data);
  }
}

class _Entry {

  String name;
  String map;
  String value;
  Widget widget;

  _Entry(this.name, this.map, this.value, this.widget);

}

