import 'package:flutter/material.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/community_repository.dart';
import 'models/notification_prefs.dart';
import 'models/pilot_group.dart';

/// Lets a pilot turn Community notifications off globally, or mute
/// individual groups. Preferences are stored in Firestore (so they sync
/// across devices) and applied when notifications are read.
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _save(BuildContext context, NotificationPrefs prefs) async {
    try {
      await CommunityRepository.instance.saveMyNotificationPrefs(prefs);
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Couldn't save: $e",
            const Icon(Icons.error, color: Colors.red), 3);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = CommunityRepository.instance;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Notification Settings"),
      ),
      body: StreamBuilder<NotificationPrefs>(
        stream: repo.watchMyNotificationPrefs(),
        builder: (context, prefsSnap) {
          if (prefsSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final prefs = prefsSnap.data ?? NotificationPrefs.defaults;
          return ListView(
            children: [
              SwitchListTile(
                title: const Text("Reply notifications"),
                subtitle: const Text(
                    "Get notified about replies to your topics and to posts in groups you own."),
                value: prefs.globalEnabled,
                onChanged: (v) =>
                    _save(context, prefs.copyWith(globalEnabled: v)),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  "PER-GROUP",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: scheme.primary,
                  ),
                ),
              ),
              if (!prefs.globalEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    "All notifications are off. Turn the switch above on to manage individual groups.",
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ),
              StreamBuilder<List<PilotGroup>>(
                stream: repo.watchMyGroups(),
                builder: (context, snap) {
                  final groups = snap.data ?? const <PilotGroup>[];
                  if (groups.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "You're not in any groups yet.",
                        style: TextStyle(color: scheme.outline),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final g in groups)
                        SwitchListTile(
                          title: Text(g.name),
                          subtitle: Text(
                            prefs.isMuted(g.id) ? "Muted" : "On",
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.outline,
                            ),
                          ),
                          // "On" means not muted. Disabled (greyed) when the
                          // global switch is off.
                          value: !prefs.isMuted(g.id),
                          onChanged: prefs.globalEnabled
                              ? (on) => _save(
                                  context, prefs.withGroupMuted(g.id, !on))
                              : null,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
