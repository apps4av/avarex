import 'package:cloud_firestore/cloud_firestore.dart';

/// A pilot's public profile shared across the Community feature.
class PilotProfile {
  final String uid;
  final String displayName;
  final String? homeAirport; // ICAO, uppercase
  final List<String> ratings;
  final List<String> aircraftTypes;
  final String? bio;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PilotProfile({
    required this.uid,
    required this.displayName,
    this.homeAirport,
    this.ratings = const [],
    this.aircraftTypes = const [],
    this.bio,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PilotProfile.empty(String uid, String? displayName) => PilotProfile(
        uid: uid,
        displayName: (displayName == null || displayName.isEmpty) ? "Pilot" : displayName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  PilotProfile copyWith({
    String? displayName,
    String? homeAirport,
    List<String>? ratings,
    List<String>? aircraftTypes,
    String? bio,
  }) {
    return PilotProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      homeAirport: homeAirport ?? this.homeAirport,
      ratings: ratings ?? this.ratings,
      aircraftTypes: aircraftTypes ?? this.aircraftTypes,
      bio: bio ?? this.bio,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        "displayName": displayName,
        "displayNameLower": displayName.toLowerCase(),
        "homeAirport": homeAirport?.toUpperCase(),
        "ratings": ratings,
        "aircraftTypes": aircraftTypes,
        "bio": bio,
        "createdAt": Timestamp.fromDate(createdAt),
        "updatedAt": Timestamp.fromDate(updatedAt),
      };

  factory PilotProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final created = data["createdAt"];
    final updated = data["updatedAt"];
    return PilotProfile(
      uid: doc.id,
      displayName: (data["displayName"] as String?) ?? "Pilot",
      homeAirport: data["homeAirport"] as String?,
      ratings: List<String>.from((data["ratings"] as List?) ?? const []),
      aircraftTypes: List<String>.from((data["aircraftTypes"] as List?) ?? const []),
      bio: data["bio"] as String?,
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
      updatedAt: updated is Timestamp ? updated.toDate() : DateTime.now(),
    );
  }
}
