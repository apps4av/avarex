import 'package:avaremp/aircraft/aircraft.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/image_utils.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';

class AircraftIconType {
  static const List<String> all = ["plane", "helicopter", "canard"];
}

class AircraftScreen extends StatefulWidget {
  const AircraftScreen({super.key});
  @override
  AircraftScreenState createState() => AircraftScreenState();

  static Future<void> reloadAircraftIcon() async {
    String iconType = Storage().settings.getAircraftIcon();
    Storage().imagePlane = await ImageUtils.loadImageFromAssets("$iconType.png");
  }
}

class AircraftScreenState extends State<AircraftScreen> {

  String? _selected;
  String _selectedIcon = Storage().settings.getAircraftIcon();

  Widget _makeContent(List<Aircraft>? items) {

    String inStorage = Storage().settings.getAircraft();

    if(null != items && items.isNotEmpty) {
      _selected = items[0].tail;
      for (Aircraft a in items) {
        if (a.tail == inStorage) {
          _selected = a.tail;
        }
      }
    }

    return Scaffold(
        appBar: AppBar(
            backgroundColor: Constants.appBarBackgroundColor,
            title: Row(
              children: [
                const Text("Aircraft"),
                const SizedBox(width: 16),
                Tooltip(
                  message: "Map Icon",
                  child: DropdownButtonHideUnderline(
                      child: DropdownButton2<String>(
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                        ),
                        isExpanded: false,
                        value: _selectedIcon,
                        items: AircraftIconType.all.map((iconType) => DropdownMenuItem<String>(
                          value: iconType,
                          child: Image.asset(
                            'assets/images/$iconType.png',
                            width: 32,
                            height: 32,
                          ),
                        )).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedIcon = value!;
                            Storage().settings.setAircraftIcon(value);
                            AircraftScreen.reloadAircraftIcon();
                          });
                        },
                      )
                  ),
                ),
              ],
            ),
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
            child: DropdownButton2<String>(
              buttonStyleData: ButtonStyleData(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
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
                  Storage().loadAircraftIds();
                });
              },
            )
        )
      ),
    ];
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

    List<_Entry> identificationEntries = [
      _Entry("Tail Number", "tail", active.tail, "Tail number, for example, N172EF."),
      _Entry("Type", "type", active.type, "Type, for example, C172."),
      _Entry("Color & Markings", "color", active.color, "Color codes: A=Amber, B=Blue, BE=Beige, BK=Black, BR=Brown, G=Green, GD=Gold, GY=Gray, M=Maroon, O=Orange, P=Purple, R=Red, S=Silver, W=White, Y=Yellow"),
      _Entry("Mode S Code", "icao", active.icao, "Mode S code in hex (registry.faa.gov), e.g. A12105."),
    ];

    List<_Entry> pilotEntries = [
      _Entry("PIC", "pic", active.pic, "Name of the pilot, for example, John Smith."),
      _Entry("PIC Information", "picInfo", active.picInfo, "Pilot information, for example, phone number."),
      _Entry("Home Base", "base", active.base, "Where the aircraft is based at, for example, KBVY."),
    ];

    List<_Entry> performanceEntries = [
      _Entry("Cruise Speed", "cruiseTas", active.cruiseTas, "Airspeed in cruise in Knots, e.g. 110."),
      _Entry("Fuel Endurance", "fuelEndurance", active.fuelEndurance, "Fuel endurance in hours, e.g. 5.5 for 5h 30m."),
      _Entry("Fuel Burn Rate", "fuelBurn", active.fuelBurn, "Fuel burn rate per hour, e.g. 10 gph."),
      _Entry("Sink Rate", "sinkRate", active.sinkRate, "Sink rate in feet per minute, e.g. 700."),
      _Entry("Wake Turbulence", "wake", active.wake, "Wake category: LIGHT, MEDIUM, or HEAVY."),
    ];

    List<_Entry> equipmentEntries = [
      _Entry("Equipment", "equipment", active.equipment, "Equipment codes: D=DME, G=GNSS, I=INS, L=ILS, O=VOR, R=PBN, S=Standard, T=TACAN, V=VHF, W=RVSM"),
      _Entry("Surveillance", "surveillance", active.surveillance, "Surveillance codes: N=None, A=Mode A, C=Modes A+C, S=Mode S, B1/B2=1090MHz, U1/U2=UAT"),
      _Entry("Other Information", "other", active.other, "Additional info: STS/, PBN/, NAV/, COM/, REG/, CODE/, RMK/"),
    ];

    List<_Entry> allEntries = [...identificationEntries, ...pilotEntries, ...performanceEntries, ...equipmentEntries];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSection("Aircraft Identification", Icons.airplanemode_active, identificationEntries),
          const SizedBox(height: 16),
          _buildSection("Pilot Information", Icons.person, pilotEntries),
          const SizedBox(height: 16),
          _buildSection("Performance", Icons.speed, performanceEntries),
          const SizedBox(height: 16),
          _buildSection("Equipment", Icons.settings_input_antenna, equipmentEntries),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [

              Padding(padding: const EdgeInsets.all(20), child: Dismissible(key: GlobalKey(),
                  background: const Icon(Icons.delete_forever),
                  direction: DismissDirection.endToStart,
                  onDismissed: (direction) {
                    String? entry = _selected;
                    if(null != entry) {
                      UserDatabaseHelper.db.deleteAircraft(entry);
                      Storage().loadAircraftIds();
                    }
                    Storage().settings.setAircraft("");
                    setState(() {
                      _selected = null;
                    });
                  },
                  child: const Column(children:[Icon(Icons.swipe_left), Text("Delete", style: TextStyle(fontSize: 8))])
              )),

              TextButton(
                onPressed: () {
                  Map<String, dynamic> mm = { for (var v in allEntries) v.map : v.value };
                  Aircraft a = Aircraft.fromMap(mm);
                  UserDatabaseHelper.db.addAircraft(a).then((value) {
                    setState(() {
                      Storage().settings.setAircraft(a.tail);
                      Storage().loadAircraftIds();
                    });
                  });
                },
                child: const Text("Save")
              ),

          ])),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<_Entry> entries) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for(_Entry e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextFormField(
                  onChanged: (value) {
                    e.value = value;
                  },
                  controller: TextEditingController()..text = e.value,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: e.name,
                    isDense: true,
                    suffixIcon: Tooltip(
                      showDuration: const Duration(seconds: 30),
                      triggerMode: TooltipTriggerMode.tap,
                      message: e.tooltip,
                      child: const Icon(Icons.info_outline, size: 20),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Aircraft>?>(
      future: UserDatabaseHelper.db.getAllAircraft(),
      builder: (BuildContext context, AsyncSnapshot<List<Aircraft>?> snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return _makeContent(snapshot.data);
        } else {
          return Container();
        }
      },
    );
  }
}

class _Entry {
  String name;
  String map;
  String value;
  String tooltip;

  _Entry(this.name, this.map, this.value, this.tooltip);
}
