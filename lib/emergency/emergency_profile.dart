import 'dart:convert';

import 'package:avaremp/checklist/checklist.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/emergency/emergency_logic.dart';

/// The permanent Emergency profile. It cannot be saved over or deleted, and
/// applying it never changes the user's settings. The only thing it stores is
/// the name of the checklist used in an emergency, in its row of the profile
/// table. That is separate from the checklist chosen on the Checklists screen.
class EmergencyProfile {
  EmergencyProfile._();

  static const String name = 'Emergency';
  static const String _checklistKey = 'checklist';

  static bool isReserved(String profileName) {
    return profileName.trim().toLowerCase() == name.toLowerCase();
  }

  /// Settings of the stored row, empty if it was never written.
  static Future<Map<String, String>> loadSettings() async {
    final List<Map<String, dynamic>> rows = await UserDatabaseHelper.db.getAllProfiles();
    for (final Map<String, dynamic> row in rows) {
      if (isReserved((row['name'] as String?) ?? '')) {
        return decode((row['settings'] as String?) ?? '');
      }
    }
    return {};
  }

  static Map<String, String> decode(String raw) {
    final Map<String, String> settings = {};
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
    return settings;
  }

  static Future<String> getChecklistName() async {
    return ((await loadSettings())[_checklistKey] ?? '').trim();
  }

  /// An empty name means the built-in checklist.
  static Future<void> setChecklistName(String checklistName) async {
    await UserDatabaseHelper.db.addProfile(
        name, jsonEncode({'emergency': 'true', _checklistKey: checklistName.trim()}));
  }

  /// Steps of the checklist chosen for the Emergency profile, or the built-in
  /// one when none is chosen or the chosen one was deleted or is empty.
  static Future<List<String>> loadSteps() async {
    final String chosen = await getChecklistName();
    if (chosen.isNotEmpty) {
      final List<Checklist> all = await UserDatabaseHelper.db.getAllChecklist();
      for (final Checklist list in all) {
        if (list.name == chosen && list.steps.isNotEmpty) {
          return List<String>.from(list.steps);
        }
      }
    }
    return List<String>.from(defaultEmergencyChecklist);
  }
}
