import 'dart:convert';

import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';

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
  static Future<bool> saveCurrent(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return UserDatabaseHelper.db.addProfile(trimmed, jsonEncode(_capture()));
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

  static Map<String, String> _capture() {
    final settings = Storage().settings;
    return {
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
  String? _selected;
  bool _loading = true;

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
      if (_selected == null ||
          !profiles
              .any((SettingsProfile profile) => profile.name == _selected)) {
        _selected = profiles.isEmpty ? null : profiles.first.name;
      }
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
    final bool saved = await ProfileStore.saveCurrent(stored);
    if (!mounted) {
      return;
    }
    if (!saved) {
      Toast.showToast(
          context, 'Could not save profile.', const Icon(Icons.error), 3);
      return;
    }
    _name.clear();
    _selected = stored;
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Saves map layers, weather, traffic volume, and instruments.',
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

  Widget _makeList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_profiles.isEmpty) {
      return const Center(child: Text('No profiles saved'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: _profiles.length + (_selected != null ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index < _profiles.length) {
          final SettingsProfile profile = _profiles[index];
          final bool selected = profile.name == _selected;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer.withAlpha(80)
                : null,
            child: ListTile(
              title: Text(profile.name),
              selected: selected,
              onTap: () {
                setState(() {
                  _selected = profile.name;
                });
              },
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Dismissible(
            key: ValueKey<String>('delete-$_selected'),
            background: const Icon(Icons.delete_forever),
            direction: DismissDirection.endToStart,
            onDismissed: (DismissDirection direction) {
              final String? entry = _selected;
              if (entry != null) {
                ProfileStore.delete(entry);
                setState(() {
                  _profiles.removeWhere(
                      (SettingsProfile item) => item.name == entry);
                  _selected = _profiles.isEmpty ? null : _profiles.first.name;
                });
              }
            },
            child: const Column(children: [
              Icon(Icons.swipe_left),
              Text('Delete', style: TextStyle(fontSize: 8))
            ]),
          ),
        );
      },
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
                InkWell(
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.bookmarks,
                            size: 24,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
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
                ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
