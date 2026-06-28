import 'package:cloud_firestore/cloud_firestore.dart';

/// A pilot's notification preferences, stored at
/// `userNotificationPrefs/{uid}`.
///
/// Preferences are applied when *reading* notifications (the actor who
/// writes a notification can't see the recipient's private prefs), so a
/// disabled global switch or a muted group hides delivered items and zeroes
/// the unread badge for that scope.
class NotificationPrefs {
  /// Master switch. When false, no Community notifications are surfaced.
  final bool globalEnabled;

  /// Group ids the user has muted individually.
  final List<String> mutedGroupIds;

  const NotificationPrefs({
    this.globalEnabled = true,
    this.mutedGroupIds = const [],
  });

  static const NotificationPrefs defaults = NotificationPrefs();

  /// Whether notifications from [groupId] should be shown.
  bool allows(String groupId) =>
      globalEnabled && !mutedGroupIds.contains(groupId);

  bool isMuted(String groupId) => mutedGroupIds.contains(groupId);

  NotificationPrefs copyWith({
    bool? globalEnabled,
    List<String>? mutedGroupIds,
  }) {
    return NotificationPrefs(
      globalEnabled: globalEnabled ?? this.globalEnabled,
      mutedGroupIds: mutedGroupIds ?? this.mutedGroupIds,
    );
  }

  /// Returns a copy with [groupId] muted or un-muted.
  NotificationPrefs withGroupMuted(String groupId, bool muted) {
    final set = List<String>.from(mutedGroupIds)..remove(groupId);
    if (muted) set.add(groupId);
    return copyWith(mutedGroupIds: set);
  }

  Map<String, dynamic> toMap() => {
        "globalEnabled": globalEnabled,
        "mutedGroupIds": mutedGroupIds,
      };

  factory NotificationPrefs.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return NotificationPrefs(
      globalEnabled: (data["globalEnabled"] as bool?) ?? true,
      mutedGroupIds:
          List<String>.from((data["mutedGroupIds"] as List?) ?? const []),
    );
  }
}
