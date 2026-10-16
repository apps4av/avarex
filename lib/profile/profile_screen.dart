import 'dart:convert';

import 'package:avaremp/aircraft/aircraft.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';

/// Which of the live flight items to store with a profile. Each is off unless
/// the pilot checks it, so applying a profile leaves the others alone.
class ProfileSaveOptions {
  final bool plan;
  final bool plate;
  final bool chartType;
  final bool aircraft;
  final bool checklist;

  const ProfileSaveOptions({
    this.plan = false,
    this.plate = false,
    this.chartType = false,
    this.aircraft = false,
    this.checklist = false,
  });
}

/// Named snapshot of the current map and display settings, stored in user.db.
class SettingsProfile {
  final String name;
  final Map<String, String> settings;

  const SettingsProfile(this.name, this.settings);

  factory SettingsProfile.fromRow(Map<String, dynamic> row) {
    final String name = (row['name'] as String?)?.trim() ?? '';
    final Map<String, String> settings = {};
    final String raw = (row['settings'] as String?) ?? '';
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final MapEntry<Object?, Object?> entry in decoded.entries) {
          if (entry.key is String && entry.value is String) {
            settings[entry.key as String] = entry.value as String;
          }
        }
      }
    } catch (_) {}
    return SettingsProfile(name, settings);
  }
}

/// Rows are stored by [UserDatabaseHelper]. Values are read and written
/// through [AppSettings] so a renamed settings key does not break a profile.
class ProfileStore {
  static Future<bool> saveCurrent(String name,
      {ProfileSaveOptions options = const ProfileSaveOptions()}) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return UserDatabaseHelper.db
        .addProfile(trimmed, jsonEncode(_capture(options)));
  }

  static String currentPlanLabel() {
    final route = Storage().route;
    final String name = route.name.trim();
    final String line = route.toString().trim();
    if (name.isEmpty && line.isEmpty) {
      return 'None';
    }
    if (line.isEmpty || (name.isNotEmpty && name != 'New Plan')) {
      return name.isEmpty ? 'None' : name;
    }
    return line;
  }

  static String currentPlateLabel() {
    final String airport =
        Storage().settings.getCurrentPlateAirport().trim();
    final String plate = Storage().currentPlate.trim();
    if (airport.isEmpty && plate.isEmpty) {
      return 'None';
    }
    if (plate.isEmpty) {
      return airport;
    }
    if (airport.isEmpty) {
      return plate;
    }
    return '$airport · $plate';
  }

  static String currentChartTypeLabel() {
    final String chart = Storage().settings.getChartType().trim();
    return chart.isEmpty ? 'None' : chart;
  }

  static String currentAircraftLabel() {
    final String performance =
        Storage().settings.getLastPerformanceAircraft().trim();
    if (performance.isNotEmpty) {
      return performance;
    }
    final String aircraft = Storage().settings.getAircraft().trim();
    return aircraft.isEmpty ? 'None' : aircraft;
  }

  static String currentChecklistLabel() {
    final String name = Storage().settings.getChecklist().trim();
    return name.isEmpty ? 'None' : name;
  }

  /// Short line of the optional items a profile will restore.
  static String includedSummary(SettingsProfile profile) {
    final Map<String, String> saved = profile.settings;
    final List<String> parts = [];
    if (saved['savePlan'] == 'true') {
      final String name =
          (saved['planLabel'] ?? saved['planName'] ?? '').trim();
      parts.add(name.isEmpty ? 'Plan' : 'Plan: $name');
    }
    if (saved['savePlate'] == 'true') {
      final String plate = (saved['plate'] ?? '').trim();
      final String airport = (saved['plateAirport'] ?? '').trim();
      final String label = plate.isEmpty ? airport : plate;
      parts.add(label.isEmpty ? 'Plate' : 'Plate: $label');
    }
    if (saved['saveChartType'] == 'true') {
      final String chart = (saved['chartType'] ?? '').trim();
      parts.add(chart.isEmpty ? 'Chart Type' : 'Chart Type: $chart');
    }
    if (saved['saveAircraft'] == 'true') {
      final String aircraft = (saved['aircraft'] ?? '').trim();
      parts.add(aircraft.isEmpty ? 'Aircraft' : 'Aircraft: $aircraft');
    }
    if (saved['saveChecklist'] == 'true') {
      final String checklist = (saved['checklist'] ?? '').trim();
      parts.add(checklist.isEmpty ? 'Checklist' : 'Checklist: $checklist');
    }
    return parts.join(' · ');
  }

  static Future<void> delete(String name) async {
    await UserDatabaseHelper.db.deleteProfile(name);
  }

  static Future<List<SettingsProfile>> loadAll() async {
    final List<Map<String, dynamic>> rows =
        await UserDatabaseHelper.db.getAllProfiles();
    return rows
        .map(SettingsProfile.fromRow)
        .where((SettingsProfile profile) => profile.name.isNotEmpty)
        .toList();
  }

  static Map<String, String> _capture(ProfileSaveOptions options) {
    final settings = Storage().settings;
    final Map<String, String> captured = {
      'layers': settings.getLayers().join(','),
      'layersOpacity':
          settings.getLayersOpacity().map((double e) => e.toString()).join(','),
      'weatherProducts': settings.getWeatherProducts().join(','),
      'weatherProductsOpacity': settings
          .getWeatherProductsOpacity()
          .map((double e) => e.toString())
          .join(','),
      'trafficPuckSize': settings.getTrafficPuckSize(),
      'instruments': settings.getInstruments(),
      'instrumentsVisible': settings.getInstrumentVisible(),
      'instrumentPositionsPortrait': settings.getInstrumentPositions(true),
      'instrumentPositionsLandscape': settings.getInstrumentPositions(false),
      'instrumentScaleFactor': settings.getInstrumentScaleFactor().toString(),
      'instrumentsLocked': settings.isInstrumentsLocked().toString(),
    };
    if (options.plan) {
      final route = Storage().route;
      captured['savePlan'] = 'true';
      captured['planName'] = route.name;
      captured['planLabel'] = currentPlanLabel();
      captured['planRoute'] = route.toJson(route.name);
      captured['planIndex'] = route.currentWaypointIndex.toString();
      captured['planDestinationIndex'] =
          (route.getCurrentWaypoint()?.currentDestinationIndex ?? 0).toString();
    }
    if (options.plate) {
      captured['savePlate'] = 'true';
      captured['plateAirport'] = settings.getCurrentPlateAirport();
      captured['plate'] = Storage().currentPlate;
    }
    if (options.chartType) {
      captured['saveChartType'] = 'true';
      captured['chartType'] = settings.getChartType();
    }
    if (options.aircraft) {
      final String performance = settings.getLastPerformanceAircraft().trim();
      captured['saveAircraft'] = 'true';
      captured['aircraft'] = performance.isNotEmpty
          ? performance
          : settings.getAircraft().trim();
    }
    if (options.checklist) {
      captured['saveChecklist'] = 'true';
      captured['checklist'] = settings.getChecklist();
    }
    return captured;
  }

  /// Restores a profile through settings setters.
  /// Layer and weather names stay in the app's current order; saved opacity
  /// is applied by name so a new layer does not disappear.
  static Future<void> apply(SettingsProfile profile) async {
    final settings = Storage().settings;
    final Map<String, String> saved = profile.settings;
    if (saved.isEmpty) {
      return;
    }

    final List<double>? layerOpacity = _mergedOpacity(
      savedNames: saved['layers'],
      savedOpacity: saved['layersOpacity'],
      currentNames: settings.getLayers(),
      currentOpacity: settings.getLayersOpacity(),
    );
    if (layerOpacity != null) {
      settings.setLayers(settings.getLayers());
      settings.setLayersOpacity(layerOpacity);
    }

    final List<double>? weatherOpacity = _mergedOpacity(
      savedNames: saved['weatherProducts'],
      savedOpacity: saved['weatherProductsOpacity'],
      currentNames: settings.getWeatherProducts(),
      currentOpacity: settings.getWeatherProductsOpacity(),
    );
    if (weatherOpacity != null) {
      settings.setWeatherProducts(settings.getWeatherProducts());
      settings.setWeatherProductsOpacity(weatherOpacity);
    }

    final String? puck = saved['trafficPuckSize'];
    if (puck != null) {
      settings.setTrafficPuckSize(puck);
    }

    final String? instruments = saved['instruments'];
    if (instruments != null) {
      settings.setInstruments(instruments);
    }
    final String? visible = saved['instrumentsVisible'];
    if (visible != null) {
      settings.setInstrumentVisible(visible);
    }
    final String? portrait = saved['instrumentPositionsPortrait'];
    if (portrait != null) {
      settings.setInstrumentPositions(true, portrait);
    }
    final String? landscape = saved['instrumentPositionsLandscape'];
    if (landscape != null) {
      settings.setInstrumentPositions(false, landscape);
    }
    final double? scale = double.tryParse(saved['instrumentScaleFactor'] ?? '');
    if (scale != null) {
      settings.setInstrumentScaleFactor(scale);
    }
    final String? locked = saved['instrumentsLocked'];
    if (locked != null) {
      settings.setInstrumentsLocked(locked == 'true');
    }

    if (saved['savePlan'] == 'true' && saved['planRoute'] != null) {
      await _restorePlan(saved);
    }

    if (saved['savePlate'] == 'true') {
      final String airport = saved['plateAirport'] ?? '';
      settings.setCurrentPlateAirport(airport);
      Storage().currentPlate = saved['plate'] ?? '';
      Storage().lastPlateAirport = airport;
      try {
        await Storage().loadPlate();
      } catch (_) {}
    }

    if (saved['saveChartType'] == 'true') {
      final String chart = (saved['chartType'] ?? '').trim();
      if (chart.isNotEmpty) {
        settings.setChartType(chart);
      }
    }

    if (saved['saveAircraft'] == 'true') {
      settings.setLastPerformanceAircraft(saved['aircraft'] ?? '');
      await Aircraft.reloadAircraftIcon();
    }

    if (saved['saveChecklist'] == 'true') {
      final String checklist = saved['checklist'] ?? '';
      settings.setChecklist(checklist);
      if (Storage().activeChecklistName != checklist) {
        Storage().activeChecklistName = '';
        Storage().activeChecklistSteps = [];
      }
    }
  }

  /// Puts a saved plan on the live route and writes it with the existing
  /// active-plan settings so a restart resumes on the same waypoint.
  static Future<void> _restorePlan(Map<String, String> saved) async {
    final String json = saved['planRoute'] ?? '';
    final String rawName = (saved['planName'] ?? '').trim();
    final String planName = rawName.isEmpty ? 'New Plan' : rawName;
    final int index = int.tryParse(saved['planIndex'] ?? '') ?? -1;
    final int destinationIndex =
        int.tryParse(saved['planDestinationIndex'] ?? '') ?? 0;
    try {
      final PlanRoute route = Storage().route;
      if (json.isEmpty || json == '[]') {
        route.clear();
        route.name = planName;
        route.update();
      } else {
        final PlanRoute restored =
            await PlanRoute.fromJson(json, planName, false);
        route.copyFrom(restored);
        if (route.length == 0) {
          route.update();
        } else if (index >= 0 && index < route.length) {
          route.setCurrentWaypoint(index);
          route.setCurrentWaypointDestinationIndex(destinationIndex);
        }
      }
      final settings = Storage().settings;
      settings.setActivePlanRoute(route.toJson(route.name));
      settings.setActivePlanName(route.name);
      settings.setActivePlanIndex(route.currentWaypointIndex);
      settings.setActivePlanDestinationIndex(
          route.getCurrentWaypoint()?.currentDestinationIndex ?? 0);
    } catch (_) {}
  }

  static List<double>? _mergedOpacity({
    required String? savedNames,
    required String? savedOpacity,
    required List<String> currentNames,
    required List<double> currentOpacity,
  }) {
    if (savedNames == null || savedOpacity == null || currentNames.isEmpty) {
      return null;
    }
    final List<String> names = savedNames.split(',');
    final List<String> raw = savedOpacity.split(',');
    final Map<String, double> byName = {};
    for (int i = 0; i < names.length; i++) {
      final String name = names[i];
      if (name.isEmpty) {
        continue;
      }
      final double value = i < raw.length ? (double.tryParse(raw[i]) ?? 0) : 0;
      byName[name] = value.clamp(0.0, 1.0).toDouble();
    }
    final List<double> merged = [];
    for (int i = 0; i < currentNames.length; i++) {
      merged.add(byName[currentNames[i]] ??
          (i < currentOpacity.length ? currentOpacity[i] : 0));
    }
    return merged;
  }
}

class SettingsProfileScreen extends StatefulWidget {
  const SettingsProfileScreen({super.key});

  @override
  State<SettingsProfileScreen> createState() => SettingsProfileScreenState();
}

class SettingsProfileScreenState extends State<SettingsProfileScreen> {
  final TextEditingController _name = TextEditingController();
  List<SettingsProfile> _profiles = [];
  bool _loading = true;
  bool _savePlan = false;
  bool _savePlate = false;
  bool _saveChartType = false;
  bool _saveAircraft = false;
  bool _saveChecklist = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final List<SettingsProfile> profiles = await ProfileStore.loadAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _profiles = profiles;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      Toast.showToast(
          context, 'Enter a profile name.', const Icon(Icons.info), 2);
      return;
    }
    final String stored = name.length > 40 ? name.substring(0, 40) : name;
    final bool saved = await ProfileStore.saveCurrent(
      stored,
      options: ProfileSaveOptions(
        plan: _savePlan,
        plate: _savePlate,
        chartType: _saveChartType,
        aircraft: _saveAircraft,
        checklist: _saveChecklist,
      ),
    );
    if (!mounted) {
      return;
    }
    if (!saved) {
      Toast.showToast(
          context, 'Could not save profile.', const Icon(Icons.error), 3);
      return;
    }
    _name.clear();
    await _reload();
    if (!mounted) {
      return;
    }
    Toast.showToast(
        context, 'Saved profile $stored.', const Icon(Icons.check), 2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text('Profile'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Profile name',
                      hintText: 'VFR day, IFR night',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                TextButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Saves map layers, weather, traffic volume, and instruments. Checked items are stored with this profile and restored when it is applied.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(child: _makeList()),
        ],
      ),
    );
  }

  Widget _optionTile({
    required String label,
    required String value,
    required bool checked,
    required ValueChanged<bool> onChanged,
  }) {
    return CheckboxListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: checked,
      onChanged: (bool? next) => onChanged(next ?? false),
      title: Text(label),
      subtitle: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _saveOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Text(
            'Also save',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        _optionTile(
          label: 'Plan',
          value: ProfileStore.currentPlanLabel(),
          checked: _savePlan,
          onChanged: (bool value) => setState(() => _savePlan = value),
        ),
        _optionTile(
          label: 'Plate',
          value: ProfileStore.currentPlateLabel(),
          checked: _savePlate,
          onChanged: (bool value) => setState(() => _savePlate = value),
        ),
        _optionTile(
          label: 'Chart Type',
          value: ProfileStore.currentChartTypeLabel(),
          checked: _saveChartType,
          onChanged: (bool value) => setState(() => _saveChartType = value),
        ),
        _optionTile(
          label: 'Aircraft',
          value: ProfileStore.currentAircraftLabel(),
          checked: _saveAircraft,
          onChanged: (bool value) => setState(() => _saveAircraft = value),
        ),
        _optionTile(
          label: 'Checklist',
          value: ProfileStore.currentChecklistLabel(),
          checked: _saveChecklist,
          onChanged: (bool value) => setState(() => _saveChecklist = value),
        ),
      ],
    );
  }

  Widget _profileCard(SettingsProfile profile) {
    final String summary = ProfileStore.includedSummary(profile);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(profile.name),
        subtitle: summary.isEmpty
            ? null
            : Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          tooltip: '',
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              child: const Text('Delete'),
              onTap: () {
                ProfileStore.delete(profile.name).then((_) {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _profiles.removeWhere(
                        (SettingsProfile item) => item.name == profile.name);
                  });
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _makeList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        _saveOptions(),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_profiles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No profiles saved')),
          )
        else
          for (final SettingsProfile profile in _profiles) _profileCard(profile),
      ],
    );
  }
}

/// Profile list shown under Map Settings. Selecting one applies that profile.
class ProfileToolsList extends StatefulWidget {
  final VoidCallback onApplied;

  const ProfileToolsList({super.key, required this.onApplied});

  @override
  State<ProfileToolsList> createState() => _ProfileToolsListState();
}

class _ProfileToolsListState extends State<ProfileToolsList> {
  late final Future<List<SettingsProfile>> _profiles = ProfileStore.loadAll();
  bool _busy = false;

  void _openProfileScreen() {
    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
        MaterialPageRoute<void>(builder: (_) => const SettingsProfileScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SettingsProfile>>(
      future: _profiles,
      builder: (BuildContext context,
          AsyncSnapshot<List<SettingsProfile>> snapshot) {
        final List<SettingsProfile> profiles = snapshot.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 16),
            InkWell(
              onTap: _openProfileScreen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
                child: Row(
                  children: [
                    Text(
                      'Profiles',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right,
                        size: 20, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
            ),
            if (snapshot.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'No saved profiles',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              )
            else
              for (final SettingsProfile profile in profiles)
                _profileRow(profile),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _profileRow(SettingsProfile profile) {
    return InkWell(
      onTap: _busy
          ? null
          : () async {
              setState(() {
                _busy = true;
              });
              await ProfileStore.apply(profile);
              if (!mounted) {
                return;
              }
              widget.onApplied();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            Icon(Icons.bookmarks,
                size: 24,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                profile.name,
                style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
