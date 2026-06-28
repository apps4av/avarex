import 'package:cloud_firestore/cloud_firestore.dart';

/// A post in a group's feed. Optionally carries:
///   * an ICAO airport tag (legacy quick-link),
///   * a shareable flight plan (space-separated waypoint IDs that match
///     PlanRoute.toString / PlanRoute.fromLine), with a human-readable
///     name for display,
///   * up to a small number of image download URLs (HTTPS, stored in
///     Firebase Storage under community/{gid}/{pid}/{n}.jpg).
///
/// Threading: posts form a single level of threaded discussion. A
/// top-level post (a "topic") has [replyToId] == null and tracks the
/// number of direct replies in [replyCount]. A reply carries the id of
/// its parent topic in [replyToId]; replies always attach to a top-level
/// topic (replies cannot themselves be replied to), which keeps a thread
/// scoped to a single conversation and the counters simple.
class GroupPost {
  static const int maxImages = 4;
  static const int maxRouteLength = 500;
  static const int maxRouteNameLength = 60;

  final String id;
  final String groupId;
  final String authorUid;
  final String authorName;
  final String text;
  final String? attachedAirport; // ICAO
  final String? attachedRouteText; // space-separated location IDs
  final String? attachedRouteName; // display label for the plan
  final List<String> mediaUrls; // HTTPS download URLs from Firebase Storage
  final String? replyToId; // parent topic id; null for a top-level topic
  final int replyCount; // direct replies; only meaningful for a topic
  final DateTime createdAt;

  const GroupPost({
    required this.id,
    required this.groupId,
    required this.authorUid,
    required this.authorName,
    required this.text,
    this.attachedAirport,
    this.attachedRouteText,
    this.attachedRouteName,
    this.mediaUrls = const [],
    this.replyToId,
    this.replyCount = 0,
    required this.createdAt,
  });

  bool get hasRoute =>
      attachedRouteText != null && attachedRouteText!.trim().isNotEmpty;

  bool get hasMedia => mediaUrls.isNotEmpty;

  /// True when this post is a reply to a topic rather than a topic itself.
  bool get isReply => replyToId != null && replyToId!.isNotEmpty;

  Map<String, dynamic> toCreateMap() => {
        "authorUid": authorUid,
        "authorName": authorName,
        "text": text,
        "attachedAirport": attachedAirport,
        "attachedRouteText": attachedRouteText,
        "attachedRouteName": attachedRouteName,
        "mediaUrls": mediaUrls,
        "replyToId": replyToId,
        "replyCount": replyCount,
        "createdAt": Timestamp.fromDate(createdAt),
      };

  factory GroupPost.fromDoc(
      String groupId, DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data["createdAt"];
    return GroupPost(
      id: doc.id,
      groupId: groupId,
      authorUid: (data["authorUid"] as String?) ?? "",
      authorName: (data["authorName"] as String?) ?? "Pilot",
      text: (data["text"] as String?) ?? "",
      attachedAirport: data["attachedAirport"] as String?,
      attachedRouteText: data["attachedRouteText"] as String?,
      attachedRouteName: data["attachedRouteName"] as String?,
      mediaUrls: List<String>.from((data["mediaUrls"] as List?) ?? const []),
      replyToId: data["replyToId"] as String?,
      replyCount: (data["replyCount"] as num?)?.toInt() ?? 0,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
