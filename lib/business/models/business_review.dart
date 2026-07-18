import 'package:cloud_firestore/cloud_firestore.dart';

/// A single review left against an [AirportBusiness].
///
/// Reviews are immutable and cannot be deleted; each is tagged with the
/// author's name (bound server-side to their profile display name) so no
/// review is anonymous.
class BusinessReview {
  static const int maxTextLength = 1000;
  static const int minRating = 1;
  static const int maxRating = 5;

  final String id;
  final int rating; // 1..5
  final String text;
  final String authorUid;
  final String authorName;
  final DateTime createdAt;

  const BusinessReview({
    required this.id,
    required this.rating,
    required this.text,
    required this.authorUid,
    required this.authorName,
    required this.createdAt,
  });

  Map<String, dynamic> toCreateMap() => {
        "rating": rating,
        "text": text.trim(),
        "authorUid": authorUid,
        "authorName": authorName,
        "createdAt": Timestamp.fromDate(createdAt),
      };

  factory BusinessReview.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final created = data["createdAt"];
    return BusinessReview(
      id: doc.id,
      rating: (data["rating"] as num?)?.toInt() ?? 0,
      text: (data["text"] as String?) ?? "",
      authorUid: (data["authorUid"] as String?) ?? "",
      authorName: (data["authorName"] as String?) ?? "Unknown",
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
    );
  }
}
