import 'dart:convert';

import 'package:avaremp/services/app_notice.dart';
import 'package:avaremp/storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Reads `appNotices` and shows each pending message in a dialog.
///
/// Failures (offline, App Check, rules) are ignored. A missing message must
/// not block the map.
class AppNoticeService {
  AppNoticeService._();

  static final AppNoticeService instance = AppNoticeService._();

  static const String collection = "appNotices";
  static const int _dismissedCap = 40;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<List<AppNotice>> fetchPending({
    required Set<String> dismissed,
    DateTime? now,
  }) async {
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
    return AppNotice.pendingOf(
      notices: notices,
      now: now ?? DateTime.now(),
      dismissed: dismissed,
    );
  }

  /// Shows pending notices one at a time. Each is remembered only after the
  /// pilot taps OK and the screen is still open.
  Future<void> present(BuildContext context) async {
    final List<AppNotice> notices;
    try {
      notices = await fetchPending(
        dismissed: _dismissedKeys(),
      );
    } catch (_) {
      return;
    }
    for (final notice in notices) {
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(notice.title),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(notice.body),
                  if (notice.url != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(notice.url!),
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

  static Set<String> _dismissedKeys() {
    final String raw = Storage().settings.getDismissedAppNotices();
    if (raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return {};
      }
      return decoded.whereType<String>().where((String item) => item.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  static void _dismiss(String dismissKey) {
    final List<String> kept = [];
    final String raw = Storage().settings.getDismissedAppNotices();
    try {
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.isNotEmpty && item != dismissKey) {
              kept.add(item);
            }
          }
        }
      }
    } catch (_) {
      kept.clear();
    }
    kept.add(dismissKey);
    final List<String> trimmed = kept.length > _dismissedCap
        ? kept.sublist(kept.length - _dismissedCap)
        : kept;
    Storage().settings.setDismissedAppNotices(jsonEncode(trimmed));
  }
}
