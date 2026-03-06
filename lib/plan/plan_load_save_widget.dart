import 'package:avaremp/data/user_database_helper.dart';

import 'plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

class PlanLoadSaveWidget extends StatefulWidget {
  const PlanLoadSaveWidget({super.key});


  @override
  State<StatefulWidget> createState() => PlanLoadSaveWidgetState();
}


class PlanLoadSaveWidgetState extends State<PlanLoadSaveWidget> {

  String _name = "";
  List<String> _currentItems = [];


  void _saveRoute(PlanRoute route) {
    UserDatabaseHelper.db.addPlan(_name, route).then((value) {
      setState(() {
        Storage().route.name = _name;
        if (!_currentItems.contains(_name)) {
          _currentItems.insert(0, Storage().route.name);
        }
      });
    });
  }

  Widget _makeContent() {
    _name = Storage().route.name;

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _name,
                    onChanged: (value) {
                      _name = value;
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Plan Name',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () {
                    _saveRoute(Storage().route);
                  },
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text("Save"),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text(
                "Saved Plans",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                "(${_currentItems.length})",
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: _currentItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 8),
                      Text("No saved plans", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                      const SizedBox(height: 4),
                      Text("Save your current plan above", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _currentItems.length,
                  itemBuilder: (context, index) {
                    final planName = _currentItems[index];
                    final isCurrentPlan = planName == Storage().route.name;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      color: isCurrentPlan ? Theme.of(context).colorScheme.primaryContainer.withAlpha(100) : null,
                      child: ListTile(
                        leading: Icon(
                          Icons.route,
                          color: isCurrentPlan ? Theme.of(context).colorScheme.primary : null,
                        ),
                        title: Text(
                          planName,
                          style: TextStyle(
                            fontWeight: isCurrentPlan ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: isCurrentPlan ? Text("Current", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)) : null,
                        trailing: PopupMenuButton(
                          tooltip: "",
                          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              child: const Text('Load'),
                              onTap: () {
                                UserDatabaseHelper.db.getPlan(planName, false).then((value) {
                                  Storage().route.copyFrom(value);
                                  Storage().route.setCurrentWaypoint(0);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                });
                              },
                            ),
                            PopupMenuItem<String>(
                              child: const Text('Load Reversed'),
                              onTap: () {
                                UserDatabaseHelper.db.getPlan(planName, true).then((value) {
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                  Storage().route.copyFrom(value);
                                  Storage().route.setCurrentWaypoint(0);
                                });
                              },
                            ),
                            PopupMenuItem<String>(
                              child: const Text('Delete'),
                              onTap: () {
                                UserDatabaseHelper.db.deletePlan(planName).then((value) {
                                  setState(() {
                                    _currentItems.removeAt(index);
                                  });
                                });
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          UserDatabaseHelper.db.getPlan(planName, false).then((value) {
                            Storage().route.copyFrom(value);
                            Storage().route.setCurrentWaypoint(0);
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          });
                        },
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
      future: UserDatabaseHelper.db.getPlans(),
      builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
        if (snapshot.hasData) {
          _currentItems = snapshot.data!;
          return _makeContent();
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}
