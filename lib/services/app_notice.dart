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
