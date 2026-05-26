import 'package:cloud_firestore/cloud_firestore.dart';

/// A post in a group's feed.
class GroupPost {
  final String id;
  final String groupId;
  final String authorUid;
  final String authorName;
  final String text;
  final String? attachedAirport; // ICAO
  final DateTime createdAt;

  const GroupPost({
    required this.id,
    required this.groupId,
    required this.authorUid,
    required this.authorName,
    required this.text,
    this.attachedAirport,
    required this.createdAt,
  });

  Map<String, dynamic> toCreateMap() => {
        "authorUid": authorUid,
        "authorName": authorName,
        "text": text,
        "attachedAirport": attachedAirport,
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
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
