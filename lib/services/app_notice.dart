/// A message published from Google Cloud (the Firebase console or the Admin
/// SDK) and shown when AvareX opens.
///
/// Collection: `appNotices/{id}`
///
///   title      string, required
///   body       string, required
///   active     bool, required (`true` to show)
///   createdAt  timestamp
///   updatedAt  timestamp — set this to now when you publish or edit so a
///              pilot who already tapped OK sees the new text
///   expiresAt  timestamp, optional — hidden once this moment has passed
///   url        string, optional — https only
///
/// Clients can read these documents and cannot write them. Publish by adding
/// or editing a document in the Firebase console. Set `active` to false, or
/// delete the document, to take a message down.
class AppNotice {
  static const int maxTitle = 120;
  static const int maxBody = 2000;
  static const int maxUrl = 500;

  final String id;
  final String title;
  final String body;
  final bool active;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final String? url;

  const AppNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.active,
    required this.updatedAt,
    required this.expiresAt,
    required this.url,
  });

  /// Token stored after the pilot taps OK. A change to the title, body,
  /// link, or [updatedAt] produces a new token, so the message is shown again.
  String get dismissKey {
    final revision = updatedAt.toUtc().millisecondsSinceEpoch;
    final content = _fnv1a("$title\n$body\n${url ?? ""}");
    return "$id@$revision@$content";
  }

  bool isCurrent(DateTime now) {
    if (!active || title.isEmpty || body.isEmpty) {
      return false;
    }
    final expiry = expiresAt;
    if (expiry != null && !expiry.isAfter(now)) {
      return false;
    }
    return true;
  }

  /// Newest current notices that this device has not dismissed.
  static List<AppNotice> pendingOf({
    required List<AppNotice> notices,
    required DateTime now,
    required Set<String> dismissed,
    int limit = 3,
  }) {
    final pending = notices
        .where((notice) =>
            notice.isCurrent(now) && !dismissed.contains(notice.dismissKey))
        .toList();
    pending.sort((a, b) {
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      if (byTime != 0) {
        return byTime;
      }
      return a.id.compareTo(b.id);
    });
    if (pending.length <= limit) {
      return pending;
    }
    return pending.sublist(0, limit);
  }

  /// Returns null when the document has no usable title and body.
  ///
  /// [readTime] converts a backend timestamp (for example a Firestore
  /// `Timestamp`) into a [DateTime]. Plain [DateTime] and epoch milliseconds
  /// are accepted without it.
  static AppNotice? tryParse(
    String id,
    Map<String, dynamic> data, {
    DateTime? Function(dynamic value)? readTime,
  }) {
    if (id.isEmpty) {
      return null;
    }
    final title = _clip(_string(data["title"]), maxTitle);
    final body = _clip(_string(data["body"]), maxBody);
    if (title.isEmpty || body.isEmpty) {
      return null;
    }
    final updated = _time(data["updatedAt"], readTime) ??
        _time(data["createdAt"], readTime) ??
        DateTime.utc(1970);
    return AppNotice(
      id: id,
      title: title,
      body: body,
      active: data["active"] == true,
      updatedAt: updated,
      expiresAt: _time(data["expiresAt"], readTime),
      url: _httpsUrl(data["url"]),
    );
  }

  static String _string(dynamic value) {
    if (value is! String) {
      return "";
    }
    return value.trim();
  }

  static String _clip(String value, int max) {
    if (value.length <= max) {
      return value;
    }
    return value.substring(0, max).trim();
  }

  static DateTime? _time(
    dynamic value,
    DateTime? Function(dynamic value)? readTime,
  ) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return readTime?.call(value);
  }

  static String? _httpsUrl(dynamic value) {
    final raw = _string(value);
    if (raw.isEmpty || raw.length > maxUrl) {
      return null;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != "https" || uri.host.isEmpty) {
      return null;
    }
    return raw;
  }

  static int _fnv1a(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}

/// A copy of an [AppNotice] kept on this device. Firestore is not written.
class StoredAppNotice {
  final String id;
  final String title;
  final String body;
  final String? url;
  final DateTime updatedAt;
  final String dismissKey;

  const StoredAppNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.url,
    required this.updatedAt,
    required this.dismissKey,
  });

  factory StoredAppNotice.fromNotice(AppNotice notice) {
    return StoredAppNotice(
      id: notice.id,
      title: notice.title,
      body: notice.body,
      url: notice.url,
      updatedAt: notice.updatedAt,
      dismissKey: notice.dismissKey,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "title": title,
      "body": body,
      "url": url,
      "updatedAt": updatedAt.toUtc().millisecondsSinceEpoch,
      "dismissKey": dismissKey,
    };
  }

  static StoredAppNotice? tryParse(dynamic value) {
    if (value is! Map) {
      return null;
    }
    final id = value["id"];
    final title = value["title"];
    final body = value["body"];
    final dismissKey = value["dismissKey"];
    final updatedAt = value["updatedAt"];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.isEmpty ||
        body is! String ||
        body.isEmpty ||
        dismissKey is! String ||
        dismissKey.isEmpty ||
        updatedAt is! int) {
      return null;
    }
    final url = value["url"];
    return StoredAppNotice(
      id: id,
      title: title,
      body: body,
      url: url is String && url.isNotEmpty ? url : null,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt, isUtc: true),
      dismissKey: dismissKey,
    );
  }
}

/// Local inbox of Apps4Av messages. One row per notice id, newest first.
class AppNoticeInbox {
  static const int cap = 40;

  /// Saves [current] into [saved]. A [deleted] dismiss key is not put back.
  /// A new dismiss key for the same id replaces that row. Messages already
  /// saved stay when they are absent from [current].
  static List<StoredAppNotice> remember({
    required List<StoredAppNotice> saved,
    required List<AppNotice> current,
    required Set<String> deleted,
  }) {
    final byId = <String, StoredAppNotice>{};
    for (final item in saved) {
      if (item.id.isEmpty || deleted.contains(item.dismissKey)) {
        continue;
      }
      byId[item.id] = item;
    }
    for (final notice in current) {
      if (deleted.contains(notice.dismissKey)) {
        final existing = byId[notice.id];
        if (existing != null && existing.dismissKey == notice.dismissKey) {
          byId.remove(notice.id);
        }
        continue;
      }
      byId[notice.id] = StoredAppNotice.fromNotice(notice);
    }
    final list = byId.values.toList();
    list.sort((a, b) {
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      if (byTime != 0) {
        return byTime;
      }
      return a.id.compareTo(b.id);
    });
    if (list.length <= cap) {
      return list;
    }
    return list.sublist(0, cap);
  }

  static List<StoredAppNotice> without(
    List<StoredAppNotice> saved,
    String dismissKey,
  ) {
    return saved.where((item) => item.dismissKey != dismissKey).toList();
  }
}
