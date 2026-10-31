import 'dart:convert';

import 'package:avaremp/aircraft/aircraft.dart';
import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/checklist/checklist.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/emergency/emergency_map_screen.dart';
import 'package:avaremp/emergency/emergency_profile.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';

/// Which live items to store with a profile. Layers, weather, traffic volume,
/// and instruments start checked. The others start unchecked.
class ProfileSaveOptions {
  final bool layers;
  final bool weather;
  final bool traffic;
  final bool instruments;
  final bool plan;
  final bool plate;
  final bool chartType;
  final bool aircraft;
  final bool checklist;

  const ProfileSaveOptions({
    this.layers = true,
    this.weather = true,
    this.traffic = true,
    this.instruments = true,
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

  /// The permanent Emergency profile. It is not applied like the others.
  bool get isEmergency => EmergencyProfile.isReserved(name);

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
    if (trimmed.isEmpty || EmergencyProfile.isReserved(trimmed)) {
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
    return performance.isEmpty ? CommonAircraftData.cessna172sp.name : performance;
  }

  static String currentChecklistLabel() {
    final String name = Storage().settings.getChecklist().trim();
    return name.isEmpty ? 'None' : name;
  }

  static String currentLayersLabel() {
    final settings = Storage().settings;
    return _onNames(settings.getLayers(), settings.getLayersOpacity());
  }

  static String currentWeatherLabel() {
    final settings = Storage().settings;
    return _onNames(
        settings.getWeatherProducts(), settings.getWeatherProductsOpacity());
  }

  static String currentTrafficLabel() {
    final String size = Storage().settings.getTrafficPuckSize().trim();
    const Map<String, String> detail = {
      'S': '20 aircraft, 3000 ft, 10 NM',
      'M': '200 aircraft, 6000 ft, 50 NM',
      'L': '1000 aircraft, 30000 ft, 500 NM',
    };
    if (size.isEmpty) {
      return 'None';
    }
    final String extra = detail[size] ?? '';
    return extra.isEmpty ? size : '$size · $extra';
  }

  static String currentInstrumentsLabel() {
    final String visible = Storage().settings.getInstrumentVisible().trim();
    return visible.isEmpty ? 'Default' : visible;
  }

  static String _onNames(List<String> names, List<double> opacity) {
    final List<String> on = [];
    for (int i = 0; i < names.length; i++) {
      final double value = i < opacity.length ? opacity[i] : 0;
      if (value > 0 && names[i].isNotEmpty) {
        on.add(names[i]);
      }
    }
    return on.isEmpty ? 'Off' : on.join(', ');
  }

  /// Profiles saved before the checkboxes have the data and no flag.
  static bool _included(
      Map<String, String> saved, String flag, String dataKey) {
    if (saved[flag] == 'true') {
      return true;
    }
    return !saved.containsKey(flag) && saved.containsKey(dataKey);
  }

  /// Short line of the items a profile will restore.
  static String includedSummary(SettingsProfile profile) {
    final Map<String, String> saved = profile.settings;
    if (profile.isEmergency) {
      final String checklist = (saved['checklist'] ?? '').trim();
      return checklist.isEmpty
          ? 'Checklist: Default'
          : 'Checklist: $checklist';
    }
    final List<String> parts = [];
    if (_included(saved, 'saveLayers', 'layers')) {
      parts.add('Layers');
    }
    if (_included(saved, 'saveWeather', 'weatherProducts')) {
      parts.add('Weather');
    }
    if (_included(saved, 'saveTraffic', 'trafficPuckSize')) {
      final String size = (saved['trafficPuckSize'] ?? '').trim();
      parts.add(size.isEmpty ? 'Traffic volume' : 'Traffic: $size');
    }
    if (_included(saved, 'saveInstruments', 'instruments')) {
      parts.add('Instruments');
    }
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
    if (EmergencyProfile.isReserved(name)) {
      return;
    }
    await UserDatabaseHelper.db.deleteProfile(name);
  }

  static Future<List<SettingsProfile>> loadAll() async {
    final List<Map<String, dynamic>> rows =
        await UserDatabaseHelper.db.getAllProfiles();
    final List<SettingsProfile> all = rows
        .map(SettingsProfile.fromRow)
        .where((SettingsProfile profile) => profile.name.isNotEmpty)
        .toList();
    // Emergency is always first, even if its row was never written.
    final Map<String, String> emergency = {};
    for (final SettingsProfile profile in all) {
      if (profile.isEmergency) {
        emergency.addAll(profile.settings);
      }
    }
    all.removeWhere((SettingsProfile profile) => profile.isEmergency);
    all.insert(0, SettingsProfile(EmergencyProfile.name, emergency));
    return all;
  }

  static Map<String, String> _capture(ProfileSaveOptions options) {
    final settings = Storage().settings;
    final Map<String, String> captured = {};
    if (options.layers) {
      captured['saveLayers'] = 'true';
      captured['layers'] = settings.getLayers().join(',');
      captured['layersOpacity'] =
          settings.getLayersOpacity().map((double e) => e.toString()).join(',');
    }
    if (options.weather) {
      captured['saveWeather'] = 'true';
      captured['weatherProducts'] = settings.getWeatherProducts().join(',');
      captured['weatherProductsOpacity'] = settings
          .getWeatherProductsOpacity()
          .map((double e) => e.toString())
          .join(',');
    }
    if (options.traffic) {
      captured['saveTraffic'] = 'true';
      captured['trafficPuckSize'] = settings.getTrafficPuckSize();
    }
    if (options.instruments) {
      captured['saveInstruments'] = 'true';
      captured['instruments'] = settings.getInstruments();
      captured['instrumentsVisible'] = settings.getInstrumentVisible();
      captured['instrumentPositionsPortrait'] =
          settings.getInstrumentPositions(true);
      captured['instrumentPositionsLandscape'] =
          settings.getInstrumentPositions(false);
      captured['instrumentScaleFactor'] =
          settings.getInstrumentScaleFactor().toString();
      captured['instrumentsLocked'] = settings.isInstrumentsLocked().toString();
    }
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
      captured['aircraft'] = performance;
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
    if (profile.isEmergency) {
      return; // Emergency opens its own screen and changes no settings
    }
    final Map<String, String> saved = profile.settings;
    if (saved.isEmpty) {
      return;
    }

    if (_included(saved, 'saveLayers', 'layers')) {
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
    }

    if (_included(saved, 'saveWeather', 'weatherProducts')) {
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
    }

    if (_included(saved, 'saveTraffic', 'trafficPuckSize')) {
      final String? puck = saved['trafficPuckSize'];
      if (puck != null) {
        settings.setTrafficPuckSize(puck);
      }
    }

    if (_included(saved, 'saveInstruments', 'instruments')) {
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
      final double? scale =
          double.tryParse(saved['instrumentScaleFactor'] ?? '');
      if (scale != null) {
        settings.setInstrumentScaleFactor(scale);
      }
      final String? locked = saved['instrumentsLocked'];
      if (locked != null) {
        settings.setInstrumentsLocked(locked == 'true');
      }
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
  List<String> _checklistNames = [];
  bool _loading = true;
  bool _saveLayers = true;
  bool _saveWeather = true;
  bool _saveTraffic = true;
  bool _saveInstruments = true;
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
    final List<Checklist> checklists =
        await UserDatabaseHelper.db.getAllChecklist();
    if (!mounted) {
      return;
    }
    setState(() {
      _profiles = profiles;
      _checklistNames = checklists.map((Checklist c) => c.name).toList();
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
    if (EmergencyProfile.isReserved(name)) {
      Toast.showToast(context, 'Emergency is a permanent profile.',
          const Icon(Icons.info), 3);
      return;
    }
    final String stored = name.length > 40 ? name.substring(0, 40) : name;
    final bool saved = await ProfileStore.saveCurrent(
      stored,
      options: ProfileSaveOptions(
        layers: _saveLayers,
        weather: _saveWeather,
        traffic: _saveTraffic,
        instruments: _saveInstruments,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _sectionHeader('New profile'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
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
                'Check the items to store with this profile. Applying the profile restores those items.',
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
        _optionTile(
          label: 'Layers',
          value: ProfileStore.currentLayersLabel(),
          checked: _saveLayers,
          onChanged: (bool value) => setState(() => _saveLayers = value),
        ),
        _optionTile(
          label: 'Weather',
          value: ProfileStore.currentWeatherLabel(),
          checked: _saveWeather,
          onChanged: (bool value) => setState(() => _saveWeather = value),
        ),
        _optionTile(
          label: 'Traffic volume',
          value: ProfileStore.currentTrafficLabel(),
          checked: _saveTraffic,
          onChanged: (bool value) => setState(() => _saveTraffic = value),
        ),
        _optionTile(
          label: 'Instruments',
          value: ProfileStore.currentInstrumentsLabel(),
          checked: _saveInstruments,
          onChanged: (bool value) => setState(() => _saveInstruments = value),
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

  Widget _emergencyCard(SettingsProfile profile) {
    final String chosen = (profile.settings['checklist'] ?? '').trim();
    final String value = _checklistNames.contains(chosen) ? chosen : '';
    PopupMenuItem<String> choice(String name, String label) {
      return PopupMenuItem<String>(
        value: name,
        child: Row(
          children: [
            SizedBox(
                width: 24,
                child: name == value
                    ? const Icon(Icons.check, size: 18, color: Colors.red)
                    : null),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
    }

    // Same tile as the other profiles, in red: name, what it holds, three-dot menu.
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.withAlpha(160), width: 1.5),
      ),
      child: ListTile(
        title: Text(profile.name,
            style: const TextStyle(
                color: Colors.red, fontWeight: FontWeight.bold)),
        subtitle: Text(ProfileStore.includedSummary(profile),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          tooltip: 'Emergency checklist',
          onSelected: (String next) async {
            await EmergencyProfile.setChecklistName(next);
            await _reload();
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              enabled: false,
              child: Text('Emergency checklist'),
            ),
            choice('', 'Default'),
            for (final String name in _checklistNames) choice(name, name),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _profileCard(SettingsProfile profile) {
    if (profile.isEmergency) {
      return _emergencyCard(profile);
    }
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
        const SizedBox(height: 8),
        const Divider(thickness: 2, height: 24),
        _sectionHeader('Saved profiles'),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final SettingsProfile profile in _profiles) _profileCard(profile),
          if (_profiles.length == 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No other profiles saved')),
            ),
        ],
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

  void _openEmergency() {
    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
        MaterialPageRoute<void>(builder: (_) => const EmergencyMapScreen()));
  }

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
    if (profile.isEmergency) {
      return InkWell(
        onTap: _openEmergency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 24, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  profile.name,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    }
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
