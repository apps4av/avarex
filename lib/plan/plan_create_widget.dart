
import 'plan_lmfs.dart';
import 'plan_route.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/storage.dart';

class PlanCreateWidget extends StatefulWidget {
  const PlanCreateWidget({super.key});

  @override
  State<StatefulWidget> createState() => PlanCreateWidgetState();
}

class PlanCreateWidgetState extends State<PlanCreateWidget> {

  String _route = Storage().settings.getLastRouteEntry();
  bool _getting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        onChanged: (value) {
                          _route = value.toUpperCase();
                        },
                        initialValue: _route.trim(),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Route',
                          hintText: 'e.g., KBOS KORD',
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      showDuration: const Duration(seconds: 30),
                      triggerMode: TooltipTriggerMode.tap,
                      message: "Create As Entered: Enter all the waypoints separated by spaces.\n\n"
                          "Create IFR Preferred Route / Show IFR ATC Routes: Enter departure and destination separated by a space.\n\n"
                          "${Storage().settings.getEmail().isEmpty ? 'Set 1800wxbrief.com account in the app introduction screen.' : 'Using 1800wxbrief.com account ${Storage().settings.getEmail()}'}",
                      child: Icon(Icons.help_outline, color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
                if (_getting)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Create As Entered'),
                  subtitle: const Text('Use waypoints exactly as typed', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_getting,
                  onTap: () {
                    String input = _route.trim();
                    Storage().settings.setLastRouteEntry(input);
                    setState(() => _getting = true);
                    PlanRoute.fromLine("New Plan", input).then((value) {
                      Storage().route.copyFrom(value);
                      Storage().route.setCurrentWaypoint(0);
                      setState(() {
                        _getting = false;
                        Navigator.pop(context);
                      });
                    });
                  },
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.alt_route),
                  title: const Text('Create IFR Preferred Route'),
                  subtitle: const Text('Fetch FAA preferred route', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_getting,
                  onTap: () {
                    String input = _route.trim();
                    Storage().settings.setLastRouteEntry(input);
                    setState(() => _getting = true);
                    PlanRoute.fromPreferred("New Plan", input, Storage().route.altitude.toString(), Storage().route.altitude.toString()).then((value) {
                      Storage().route.copyFrom(value);
                      Storage().route.setCurrentWaypoint(0);
                      setState(() {
                        _getting = false;
                        Navigator.pop(context);
                      });
                    });
                  },
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('Show IFR ATC Routes'),
                  subtitle: const Text('View recently cleared routes', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_getting,
                  onTap: () {
                    String input = _route.trim();
                    Storage().settings.setLastRouteEntry(input);
                    setState(() => _getting = true);
                    LmfsInterface interface = LmfsInterface();
                    List<String> wps = input.split(" ");
                    if (wps.length < 2) {
                      setState(() => _getting = false);
                      return;
                    }
                    interface.getRoute(wps[0], wps[1]).then((value) {
                      setState(() {
                        _getting = false;
                        showDialog<String>(
                          context: context,
                          builder: (BuildContext context) => Dialog.fullscreen(
                            child: Scaffold(
                              appBar: AppBar(
                                title: Text("ATC Routes: ${wps[0]} → ${wps[1]}"),
                                leading: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                              body: value.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.search_off, size: 48, color: Theme.of(context).colorScheme.outline),
                                          const SizedBox(height: 8),
                                          const Text("No routes found"),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: value.length,
                                      itemBuilder: (context, index) {
                                        return Card(
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                              child: Text("${index + 1}"),
                                            ),
                                            title: SelectableText(value[index].route),
                                            subtitle: Text(
                                              "Last departure: ${value[index].lastDepartureTime.toString().substring(0, 16)}",
                                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        );
                      });
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
