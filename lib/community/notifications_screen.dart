import 'package:flutter/material.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/community_repository.dart';
import 'models/community_notification.dart';
import 'models/notification_prefs.dart';
import 'notification_settings_screen.dart';
import 'post_thread_screen.dart';

/// App-bar bell with an unread badge. The badge respects the user's
/// notification preferences: muted groups and a global "off" switch do not
/// contribute to the count.
class CommunityNotificationsBell extends StatelessWidget {
  const CommunityNotificationsBell({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = CommunityRepository.instance;
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<NotificationPrefs>(
      stream: repo.watchMyNotificationPrefs(),
      builder: (context, prefsSnap) {
        final prefs = prefsSnap.data ?? NotificationPrefs.defaults;
        return StreamBuilder<List<CommunityNotification>>(
          stream: repo.watchMyNotifications(),
          builder: (context, snap) {
            final items = snap.data ?? const <CommunityNotification>[];
            final unread = items
                .where((n) => !n.read && prefs.allows(n.groupId))
                .length;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: Icon(prefs.globalEnabled
                      ? Icons.notifications_none
                      : Icons.notifications_off_outlined),
                  tooltip: "Notifications",
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen()),
                  ),
                ),
                if (unread > 0)
                  Positioned(
                    top: 6,
                    right: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      child: Text(
                        unread > 99 ? "99+" : "$unread",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Compact bell + unread-count badge meant to be overlaid on top of
/// another label (e.g. the "Community" entry on the login screen). Tapping
/// opens the notifications list. The unread count respects the user's
/// notification preferences (muted groups / global off don't count), and
/// the bell shows an "off" glyph when notifications are globally disabled.
class CommunityNotificationsBadge extends StatelessWidget {
  final double iconSize;
  const CommunityNotificationsBadge({super.key, this.iconSize = 18});

  @override
  Widget build(BuildContext context) {
    final repo = CommunityRepository.instance;
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<NotificationPrefs>(
      stream: repo.watchMyNotificationPrefs(),
      builder: (context, prefsSnap) {
        final prefs = prefsSnap.data ?? NotificationPrefs.defaults;
        return StreamBuilder<List<CommunityNotification>>(
          stream: repo.watchMyNotifications(),
          builder: (context, snap) {
            final items = snap.data ?? const <CommunityNotification>[];
            final unread = items
                .where((n) => !n.read && prefs.allows(n.groupId))
                .length;
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    prefs.globalEnabled
                        ? Icons.notifications_none
                        : Icons.notifications_off_outlined,
                    size: iconSize,
                  ),
                  if (unread > 0)
                    Positioned(
                      top: -5,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(minWidth: 14),
                        child: Text(
                          unread > 99 ? "99+" : "$unread",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return "just now";
    if (d.inHours < 1) return "${d.inMinutes}m ago";
    if (d.inDays < 1) return "${d.inHours}h ago";
    if (d.inDays < 7) return "${d.inDays}d ago";
    final w = d.inDays ~/ 7;
    if (w < 5) return "${w}w ago";
    final mo = d.inDays ~/ 30;
    if (mo < 12) return "${mo}mo ago";
    return "${d.inDays ~/ 365}y ago";
  }

  String _reasonText(CommunityNotification n) => n.isOwnerReason
      ? "${n.actorName} replied in your group ${n.groupName}"
      : "${n.actorName} replied to your topic in ${n.groupName}";

  Future<void> _open(
      BuildContext context, CommunityNotification n) async {
    final repo = CommunityRepository.instance;
    // Mark read first so the badge updates even if navigation is cancelled.
    try {
      if (!n.read) await repo.markNotificationRead(n.id);
    } catch (_) {/* non-fatal */}
    final membership = await repo.fetchMyMembership(n.groupId);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostThreadScreen(
          groupId: n.groupId,
          groupName: n.groupName,
          topicId: n.topicId,
          isOwner: membership?.isOwner ?? false,
          canPost: membership?.isActive ?? false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = CommunityRepository.instance;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Notifications"),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: "Mark all read",
            onPressed: () async {
              try {
                await repo.markAllNotificationsRead();
              } catch (e) {
                if (context.mounted) {
                  Toast.showToast(context, "Couldn't update: $e",
                      const Icon(Icons.error, color: Colors.red), 3);
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Notification settings",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<NotificationPrefs>(
        stream: repo.watchMyNotificationPrefs(),
        builder: (context, prefsSnap) {
          final prefs = prefsSnap.data ?? NotificationPrefs.defaults;
          return StreamBuilder<List<CommunityNotification>>(
            stream: repo.watchMyNotifications(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snap.data ?? const <CommunityNotification>[];
              // Apply preferences on read: hide muted groups, and hide
              // everything when notifications are globally off.
              final visible =
                  all.where((n) => prefs.allows(n.groupId)).toList();

              return Column(
                children: [
                  if (!prefs.globalEnabled)
                    _OffBanner(
                      onManage: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const NotificationSettingsScreen()),
                      ),
                    ),
                  Expanded(
                    child: visible.isEmpty
                        ? _EmptyNotifications(
                            globalEnabled: prefs.globalEnabled)
                        : ListView.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final n = visible[i];
                              return Dismissible(
                                key: ValueKey(n.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  color: scheme.errorContainer,
                                  padding:
                                      const EdgeInsets.only(right: 20),
                                  child: Icon(Icons.delete_outline,
                                      color: scheme.onErrorContainer),
                                ),
                                onDismissed: (_) async {
                                  try {
                                    await repo.deleteNotification(n.id);
                                  } catch (_) {/* best effort */}
                                },
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: n.read
                                        ? scheme.surfaceContainerHighest
                                        : scheme.primaryContainer,
                                    child: Icon(
                                      Icons.reply,
                                      size: 20,
                                      color: n.read
                                          ? scheme.outline
                                          : scheme.onPrimaryContainer,
                                    ),
                                  ),
                                  title: Text(
                                    _reasonText(n),
                                    style: TextStyle(
                                      fontWeight: n.read
                                          ? FontWeight.normal
                                          : FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (n.snippet.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 2, bottom: 2),
                                          child: Text(
                                            n.snippet,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: scheme.onSurfaceVariant,
                                              fontWeight: n.read
                                                  ? FontWeight.normal
                                                  : FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        _relativeTime(n.createdAt),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.outline),
                                      ),
                                    ],
                                  ),
                                  trailing: n.read
                                      ? null
                                      : Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: scheme.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                  isThreeLine: n.snippet.isNotEmpty,
                                  onTap: () => _open(context, n),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _OffBanner extends StatelessWidget {
  final VoidCallback onManage;
  const _OffBanner({required this.onManage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest.withAlpha(150),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 18, color: scheme.outline),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Notifications are turned off. New replies won't be shown.",
              style: TextStyle(fontSize: 12),
            ),
          ),
          TextButton(onPressed: onManage, child: const Text("Manage")),
        ],
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  final bool globalEnabled;
  const _EmptyNotifications({required this.globalEnabled});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              globalEnabled ? "You're all caught up" : "Notifications are off",
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              globalEnabled
                  ? "You'll be notified when someone replies to your topics, or to any post in a group you own."
                  : "Turn notifications on in settings to see replies to your topics and your groups.",
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
