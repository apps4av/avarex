import 'package:cloud_firestore/cloud_firestore.dart';

/// An in-app notification delivered to a pilot under
/// `userNotifications/{recipientUid}/items/{id}`.
///
/// There are no Cloud Functions in v1, so notifications are written by the
/// actor (e.g. the person who posted a reply) directly into each
/// recipient's collection at the time of the action. Recipients apply
/// their own [NotificationPrefs] when reading, so muting a group or
/// disabling notifications globally simply hides delivered items rather
/// than preventing the write.
class CommunityNotification {
  static const String typeReply = 'reply';

  /// The recipient is the author of the topic that was replied to.
  static const String reasonTopicAuthor = 'topic_author';

  /// The recipient owns the group the reply was posted in.
  static const String reasonGroupOwner = 'group_owner';

  static const int maxSnippet = 140;

  final String id;
  final String type;
  final String groupId;
  final String groupName;
  final String topicId; // the top-level topic the thread belongs to
  final String postId; // the reply that triggered this notification
  final String actorUid; // who replied
  final String actorName;
  final String reason; // why this recipient was notified
  final String snippet; // short preview of the reply
  final bool read;
  final DateTime createdAt;

  const CommunityNotification({
    required this.id,
    required this.type,
    required this.groupId,
    required this.groupName,
    required this.topicId,
    required this.postId,
    required this.actorUid,
    required this.actorName,
    required this.reason,
    required this.snippet,
    required this.read,
    required this.createdAt,
  });

  bool get isOwnerReason => reason == reasonGroupOwner;

  Map<String, dynamic> toCreateMap() => {
        "type": type,
        "groupId": groupId,
        "groupName": groupName,
        "topicId": topicId,
        "postId": postId,
        "actorUid": actorUid,
        "actorName": actorName,
        "reason": reason,
        "snippet": snippet,
        "read": read,
        "createdAt": Timestamp.fromDate(createdAt),
      };

  factory CommunityNotification.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data["createdAt"];
    return CommunityNotification(
      id: doc.id,
      type: (data["type"] as String?) ?? typeReply,
      groupId: (data["groupId"] as String?) ?? "",
      groupName: (data["groupName"] as String?) ?? "Group",
      topicId: (data["topicId"] as String?) ?? "",
      postId: (data["postId"] as String?) ?? "",
      actorUid: (data["actorUid"] as String?) ?? "",
      actorName: (data["actorName"] as String?) ?? "Pilot",
      reason: (data["reason"] as String?) ?? reasonTopicAuthor,
      snippet: (data["snippet"] as String?) ?? "",
      read: (data["read"] as bool?) ?? false,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
