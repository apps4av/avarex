import 'plan_file_widget.dart';
import 'plan_lmfs.dart';
import 'package:flutter/material.dart';

import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/twilight_calculator.dart';
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
  Color? _errorColor;

  Future<LmfsPlanList> getPlans() async {
    LmfsPlanList ret;
    LmfsInterface interface = LmfsInterface();
    ret = await interface.getFlightPlans();
    return ret;
  }

  Color _getStateColor(String state) {
    switch (state) {
      case "ACTIVE":
        return Colors.green;
      case "PROPOSED":
        return Colors.blue;
      case "CLOSED":
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  IconData _getStateIcon(String state) {
    switch (state) {
      case "ACTIVE":
        return Icons.flight_takeoff;
      case "PROPOSED":
        return Icons.schedule;
      case "CLOSED":
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }

  Widget _makeContent(LmfsPlanList? plans) {

    bool getting = false;
    if (plans == null) {
      getting = true;
      plans = LmfsPlanList("{}");
    }

    List<LmfsPlanListPlan> items = plans.getPlans();
    DateTime? sunset;
    DateTime? sunrise;
    (sunrise, sunset) = TwilightCalculator.calculateTwilight(Storage().position.latitude, Storage().position.longitude);

    if (getting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flight_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            Text("No flight plans on file", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 4),
            Text("File a plan in Brief & File", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text(
                "Flight Plans",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                "(${items.length})",
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
              const Spacer(),
              if (_sending)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              if (_error.isNotEmpty && !_sending)
                Tooltip(
                  message: _error,
                  child: Icon(
                    _errorColor == Colors.red ? Icons.error : Icons.info_outline,
                    size: 16,
                    color: _errorColor ?? Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemBuilder: (context, index) {
              final LmfsPlanListPlan item = items[index];
              final stateColor = _getStateColor(item.currentState);
              
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_getStateIcon(item.currentState), color: stateColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${item.departure} → ${item.destination}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Text(
                                  item.aircraftId,
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: stateColor.withAlpha(30),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: stateColor),
                            ),
                            child: Text(
                              item.currentState,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: stateColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (item.currentState == "PROPOSED") ...[
                            TextButton(
                              onPressed: () {
                                LmfsInterface interface = LmfsInterface();
                                setState(() {
                                  _sending = true;
                                  _error = "";
                                });
                                interface.cancelFlightPlan(item.id).then((value) => setState(() {
                                  _error = interface.error;
                                  if (_error.isNotEmpty) {
                                    _errorColor = Colors.red;
                                  }
                                  _sending = false;
                                }));
                              },
                              child: const Text("Cancel"),
                            ),
                            const SizedBox(width: 8),
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
                                        if (_error.isNotEmpty) {
                                          _errorColor = Colors.red;
                                        }
                                        _sending = false;
                                      }));
                                    },
                                  ),
                                );
                              },
                              child: const Text("Depart"),
                            ),
                          ],
                          if (item.currentState == "ACTIVE")
                            TextButton(
                              onPressed: () {
                                LmfsInterface interface = LmfsInterface();
                                setState(() {
                                  _sending = true;
                                  _error = "";
                                });
                                interface.closeFlightPlan(item.id).then((value) => setState(() {
                                  _error = interface.error;
                                  if (_error.isNotEmpty) {
                                    _errorColor = Colors.red;
                                  }
                                  _sending = false;
                                }));
                              },
                              child: const Text("Close"),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {

    return FutureBuilder(
        future: getPlans(),
        builder: (context, snapshot) {
          return _makeContent(snapshot.data);
        });
  }

}
