import 'dart:convert';

import 'package:avaremp/services/app_notice.dart';
import 'package:avaremp/storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Reads `appNotices` and shows each pending message in a dialog.
///
/// Current messages are also copied into local settings until the pilot
/// deletes them. This client does not write Firestore.
///
/// Failures (offline, App Check, rules) are ignored. A missing message must
/// not block the map.
class AppNoticeService {
  AppNoticeService._();

  static final AppNoticeService instance = AppNoticeService._();

  static const String collection = "appNotices";
  static const int _tokenCap = 40;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<List<AppNotice>> fetchPending({
    required Set<String> dismissed,
    DateTime? now,
  }) async {
    final notices = await _readActive();
    return AppNotice.pendingOf(
      notices: notices,
      now: now ?? DateTime.now(),
      dismissed: dismissed,
    );
  }

  /// Messages kept on this device, newest first.
  List<StoredAppNotice> saved() => _loadSaved();

  /// Drops one saved message. That revision is not saved or popped up again.
  void deleteSaved(StoredAppNotice notice) {
    _writeSaved(AppNoticeInbox.without(_loadSaved(), notice.dismissKey));
    _rememberToken(
      read: Storage().settings.getDeletedAppNotices,
      write: Storage().settings.setDeletedAppNotices,
      token: notice.dismissKey,
    );
    _dismiss(notice.dismissKey);
  }

  /// Shows pending notices one at a time. Each current message is saved
  /// before the popup. OK only suppresses the popup.
  Future<void> present(BuildContext context) async {
    final List<AppNotice> notices;
    try {
      notices = await _readActive();
    } catch (_) {
      return;
    }
    final DateTime now = DateTime.now();
    final List<AppNotice> current =
        notices.where((AppNotice notice) => notice.isCurrent(now)).toList();
    _remember(current);
    final List<AppNotice> pending = AppNotice.pendingOf(
      notices: notices,
      now: now,
      dismissed: _keys(Storage().settings.getDismissedAppNotices()),
    );
    for (final notice in pending) {
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final TextStyle? titleStyle =
              Theme.of(dialogContext).textTheme.titleLarge;
          final Color linkColor = Theme.of(dialogContext).colorScheme.primary;
          return AlertDialog(
            title: SelectableText(notice.title, style: titleStyle),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(notice.body),
                  if (notice.url != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      notice.url!,
                      style: TextStyle(color: linkColor),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text("OK"),
              ),
            ],
          );
        },
      );
      if (!context.mounted) {
        return;
      }
      _dismiss(notice.dismissKey);
    }
  }

  Future<List<AppNotice>> _readActive() async {
    final snap = await _db
        .collection(collection)
        .where("active", isEqualTo: true)
        .limit(20)
        .get()
        .timeout(const Duration(seconds: 8));
    final notices = <AppNotice>[];
    for (final doc in snap.docs) {
      final notice = AppNotice.tryParse(
        doc.id,
        doc.data(),
        readTime: (value) => value is Timestamp ? value.toDate() : null,
      );
      if (notice != null) {
        notices.add(notice);
      }
    }
    return notices;
  }

  void _remember(List<AppNotice> current) {
    final List<StoredAppNotice> next = AppNoticeInbox.remember(
      saved: _loadSaved(),
      current: current,
      deleted: _keys(Storage().settings.getDeletedAppNotices()),
    );
    _writeSaved(next);
  }

  static List<StoredAppNotice> _loadSaved() {
    final String raw = Storage().settings.getSavedAppNotices();
    if (raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .map(StoredAppNotice.tryParse)
          .whereType<StoredAppNotice>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void _writeSaved(List<StoredAppNotice> notices) {
    Storage().settings.setSavedAppNotices(
          jsonEncode(notices
              .map((StoredAppNotice notice) => notice.toJson())
              .toList()),
        );
  }

  static void _dismiss(String dismissKey) {
    _rememberToken(
      read: Storage().settings.getDismissedAppNotices,
      write: Storage().settings.setDismissedAppNotices,
      token: dismissKey,
    );
  }

  static Set<String> _keys(String raw) {
    if (raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return {};
      }
      return decoded
          .whereType<String>()
          .where((String item) => item.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static void _rememberToken({
    required String Function() read,
    required void Function(String value) write,
    required String token,
  }) {
    final List<String> kept = [];
    try {
      final String raw = read();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.isNotEmpty && item != token) {
              kept.add(item);
            }
          }
        }
      }
    } catch (_) {
      kept.clear();
    }
    kept.add(token);
    final List<String> trimmed =
        kept.length > _tokenCap ? kept.sublist(kept.length - _tokenCap) : kept;
    write(jsonEncode(trimmed));
  }
}
