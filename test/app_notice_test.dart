import 'package:avaremp/services/app_notice.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotice _notice({
  String id = "cycle",
  String title = "Chart cycle",
  String body = "New charts are available.",
  bool active = true,
  DateTime? updatedAt,
  DateTime? expiresAt,
  String? url,
}) {
  return AppNotice(
    id: id,
    title: title,
    body: body,
    active: active,
    updatedAt: updatedAt ?? DateTime.utc(2026, 10, 1),
    expiresAt: expiresAt,
    url: url,
  );
}

void main() {
  final DateTime now = DateTime.utc(2026, 10, 18);

  group("AppNotice.tryParse", () {
    test("reads a console document", () {
      final notice = AppNotice.tryParse("cycle-2513", {
        "title": " Chart cycle ",
        "body": "Download the new cycle.",
        "active": true,
        "updatedAt": DateTime.utc(2026, 10, 2),
        "expiresAt": DateTime.utc(2026, 11, 1),
        "url": "https://apps4av.net/cycle",
      });
      expect(notice, isNotNull);
      expect(notice!.title, "Chart cycle");
      expect(notice.url, "https://apps4av.net/cycle");
      expect(notice.isCurrent(now), isTrue);
    });

    test("drops a document with no text", () {
      expect(AppNotice.tryParse("x", {"title": " ", "body": "hi", "active": true}), isNull);
    });

    test("ignores a non-https link", () {
      final notice = AppNotice.tryParse("x", {
        "title": "Hello",
        "body": "World",
        "active": true,
        "url": "http://example.com",
      });
      expect(notice!.url, isNull);
    });
  });

  group("AppNotice.pendingOf", () {
    test("hides inactive, expired, and dismissed notices", () {
      final current = _notice(id: "new");
      final pending = AppNotice.pendingOf(
        now: now,
        dismissed: {_notice(id: "seen").dismissKey},
        notices: [
          current,
          _notice(id: "off", active: false),
          _notice(id: "old", expiresAt: DateTime.utc(2026, 10, 1)),
          _notice(id: "seen"),
        ],
      );
      expect(pending.map((notice) => notice.id), ["new"]);
    });

    test("an edit shows a dismissed notice again", () {
      final original = _notice(body: "First text");
      final edited = _notice(
        body: "Updated text",
        updatedAt: DateTime.utc(2026, 10, 3),
      );
      expect(original.dismissKey, isNot(edited.dismissKey));
      final pending = AppNotice.pendingOf(
        now: now,
        dismissed: {original.dismissKey},
        notices: [edited],
      );
      expect(pending, hasLength(1));
    });

    test("orders newest first and caps the list", () {
      final pending = AppNotice.pendingOf(
        now: now,
        dismissed: const {},
        limit: 2,
        notices: [
          _notice(id: "a", updatedAt: DateTime.utc(2026, 1, 1)),
          _notice(id: "c", updatedAt: DateTime.utc(2026, 3, 1)),
          _notice(id: "b", updatedAt: DateTime.utc(2026, 2, 1)),
        ],
      );
      expect(pending.map((notice) => notice.id), ["c", "b"]);
    });
  });
}
