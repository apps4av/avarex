import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import '../../community/data/community_repository.dart';
import '../models/airport_business.dart';
import '../models/business_review.dart';

/// All Firestore interaction for the crowd-sourced Airport Businesses
/// feature is funneled through this repository so screens never touch
/// Firestore directly.
///
/// Collection layout:
///   airportBusinesses/{bizId}                 -> AirportBusiness
///   airportBusinesses/{bizId}/reviews/{rid}   -> BusinessReview
///
/// Contributor identity (createdByName / authorName) is bound to the
/// pilot's Community profile display name, both here and in the security
/// rules, so no listing or review can be posted anonymously or under a
/// spoofed name. Entries and reviews can be created but never deleted.
class AirportBusinessRepository {
  AirportBusinessRepository._();
  static final AirportBusinessRepository instance =
      AirportBusinessRepository._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw StateError("Not signed in");
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection("airportBusinesses");

  DocumentReference<Map<String, dynamic>> _bizRef(String bizId) =>
      _col.doc(bizId);

  CollectionReference<Map<String, dynamic>> _reviewsCol(String bizId) =>
      _bizRef(bizId).collection("reviews");

  /// Ensure the caller has a Community profile (so their display name is
  /// available to tag contributions with) and return that display name.
  Future<String> _requireDisplayName() async {
    final profile = await CommunityRepository.instance.ensureMyProfile();
    return profile.displayName;
  }

  // -------------------- Businesses --------------------

  /// Live list of businesses at [airport]. Listings that pilots have created
  /// or modified are floated to the top; the rest are ordered nearest-first
  /// from [origin] (the airport's coordinate) when supplied, else
  /// alphabetically. Requires the composite index
  /// (airport ASC, nameLower ASC) in firestore.indexes.json.
  Stream<BusinessListSnapshot> watchBusinesses(String airport,
      {LatLng? origin, int limit = 200}) {
    final id = airport.trim().toUpperCase();
    if (id.isEmpty) {
      return Stream.value(
          const BusinessListSnapshot([], isFromCache: false));
    }
    return _col
        .where("airport", isEqualTo: id)
        .orderBy("nameLower")
        .limit(limit)
        .snapshots()
        .map((s) {
      final list = s.docs.map(AirportBusiness.fromDoc).toList();
      list.sort(AirportBusiness.byDistanceInteractedFirst(origin));
      return BusinessListSnapshot(list, isFromCache: s.metadata.isFromCache);
    });
  }

  /// One-shot fetch of the businesses at [airport] that carry a map
  /// coordinate. Used by the plate diagram to draw business markers. Returns
  /// an empty list on any failure (not signed in, offline, missing index),
  /// so callers can treat it as a best-effort overlay.
  Future<List<AirportBusiness>> fetchBusinessesWithLocation(String airport,
      {LatLng? origin, int limit = 200}) async {
    final id = airport.trim().toUpperCase();
    if (id.isEmpty) return const [];
    try {
      final snap = await _col
          .where("airport", isEqualTo: id)
          .orderBy("nameLower")
          .limit(limit)
          .get();
      final list = snap.docs
          .map(AirportBusiness.fromDoc)
          .where((b) => b.hasLocation)
          .toList();
      // Same ordering as the long-press list (interacted first, then
      // nearest-first from the airport) so the plate selector matches.
      list.sort(AirportBusiness.byDistanceInteractedFirst(origin));
      return list;
    } catch (_) {
      return const [];
    }
  }

  Stream<AirportBusiness?> watchBusiness(String bizId) {
    return _bizRef(bizId)
        .snapshots()
        .map((s) => s.exists ? AirportBusiness.fromDoc(s) : null);
  }

  /// Review aggregates for a business, computed server-side via an
  /// aggregation query over the immutable reviews subcollection. There are
  /// no stored counters to tamper with, so the result always reflects real
  /// review documents.
  Future<BusinessStats> fetchStats(String bizId) async {
    try {
      final snap = await _reviewsCol(bizId)
          .aggregate(count(), average("rating"))
          .get();
      final c = snap.count ?? 0;
      if (c == 0) return BusinessStats.empty;
      final avg = snap.getAverage("rating") ?? 0;
      return BusinessStats(reviewCount: c, averageRating: avg.toDouble());
    } catch (_) {
      // Aggregation queries are server-only; offline (or on any error) we
      // can't compute them. Signal "unavailable" so the UI doesn't show a
      // misleading "no reviews".
      return BusinessStats.unavailable;
    }
  }

  /// Add a new business listing for [airport]. The current user becomes the
  /// creator of record.
  Future<String> addBusiness({
    required String airport,
    required String name,
    List<String> services = const [],
    List<String> fuelTypes = const [],
    String operatingHours = "",
    String phoneNumber = "",
    String radioFrequency = "",
  }) async {
    final uid = _requireUid();
    final displayName = await _requireDisplayName();

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError("Business name is required");
    }
    if (trimmedName.length > AirportBusiness.maxNameLength) {
      throw StateError("Business name is too long");
    }

    final ref = _col.doc();
    final biz = AirportBusiness(
      id: ref.id,
      airport: airport.trim().toUpperCase(),
      name: trimmedName,
      services: _sanitize(services, AirportBusiness.maxServices),
      fuelTypes: _sanitize(fuelTypes, AirportBusiness.maxFuelTypes),
      operatingHours: _clampHours(operatingHours),
      phoneNumber: _clampPhone(phoneNumber),
      radioFrequency: _clampFrequency(radioFrequency),
      createdByUid: uid,
      createdByName: displayName,
      source: "user",
      createdAt: DateTime.now(),
    );
    final data = biz.toCreateMap();
    // Server-pin the creation time; the rules require createdAt == request.time
    // so a client-chosen timestamp would be rejected.
    data["createdAt"] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  /// Enrich an existing listing with services / fuel / hours. Any signed-in
  /// contributor may add detail (the data is crowd-sourced); the listing's
  /// identity, creator and review aggregates are immutable. Every edit is
  /// attributed to the editor so detail changes are never anonymous.
  Future<void> updateDetails(
    String bizId, {
    required List<String> services,
    required List<String> fuelTypes,
    required String operatingHours,
    required String phoneNumber,
    required String radioFrequency,
  }) async {
    final uid = _requireUid();
    final displayName = await _requireDisplayName();
    await _bizRef(bizId).update({
      "services": _sanitize(services, AirportBusiness.maxServices),
      "fuelTypes": _sanitize(fuelTypes, AirportBusiness.maxFuelTypes),
      "operatingHours": _clampHours(operatingHours),
      "phoneNumber": _clampPhone(phoneNumber),
      "radioFrequency": _clampFrequency(radioFrequency),
      "lastEditedByUid": uid,
      "lastEditedByName": displayName,
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }

  /// Set the per-fuel-type prices for a listing. [prices] is the desired
  /// fuel-type -> price map (types omitted are removed). Prices that are
  /// unchanged from [previous] keep their original "last set" date; new or
  /// changed prices are stamped with the server time. Attributed like any
  /// other detail edit.
  Future<void> setFuelPrices(
    String bizId, {
    required Map<String, double> prices,
    required Map<String, FuelPrice> previous,
  }) async {
    final uid = _requireUid();
    final displayName = await _requireDisplayName();

    final Map<String, dynamic> fuelPrices = {};
    var count = 0;
    prices.forEach((type, price) {
      final t = type.trim();
      if (t.isEmpty || count >= AirportBusiness.maxFuelPrices) return;
      if (!price.isFinite || price < 0 || price > 100) return;
      final rounded = double.parse(price.toStringAsFixed(2));
      final prev = previous[t];
      fuelPrices[t] = {
        "price": rounded,
        // Keep the old date when the price hasn't changed; otherwise pin to
        // the server clock so the "last set" date is trustworthy.
        "updatedAt": (prev != null && prev.price == rounded)
            ? Timestamp.fromDate(prev.updatedAt ?? DateTime.now())
            : FieldValue.serverTimestamp(),
      };
      count++;
    });

    await _bizRef(bizId).update({
      "fuelPrices": fuelPrices,
      "lastEditedByUid": uid,
      "lastEditedByName": displayName,
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }

  // -------------------- Reviews --------------------

  Stream<List<BusinessReview>> watchReviews(String bizId, {int limit = 200}) {
    return _reviewsCol(bizId)
        .orderBy("createdAt", descending: true)
        .limit(limit)
        .snapshots()
        .map((s) =>
            s.docs.map(BusinessReview.fromDoc).toList(growable: false));
  }

  /// Post a review. Creates the immutable review document only. Review
  /// aggregates are not stored on the listing; the average and count are
  /// computed on demand from the reviews subcollection via [fetchStats], so
  /// the displayed rating always reflects real, attributable reviews and
  /// cannot be forged from the client.
  Future<void> addReview(
    String bizId, {
    required int rating,
    required String text,
  }) async {
    final uid = _requireUid();
    final displayName = await _requireDisplayName();

    if (rating < BusinessReview.minRating || rating > BusinessReview.maxRating) {
      throw StateError("Rating must be between 1 and 5");
    }
    final trimmed = text.trim();
    if (trimmed.length > BusinessReview.maxTextLength) {
      throw StateError("Review is too long");
    }

    // One review per pilot per business: use the uid as the review id so a
    // repeat review collides with the existing (immutable) one. Enforced by
    // the security rules too; the pre-check just yields a friendlier error.
    final reviewRef = _reviewsCol(bizId).doc(uid);
    final existing = await reviewRef.get();
    if (existing.exists) {
      throw StateError("You have already reviewed this business.");
    }
    final review = BusinessReview(
      id: reviewRef.id,
      rating: rating,
      text: trimmed,
      authorUid: uid,
      authorName: displayName,
      createdAt: DateTime.now(),
    );
    final data = review.toCreateMap();
    // Server-pin creation time; rules require createdAt == request.time.
    data["createdAt"] = FieldValue.serverTimestamp();

    // Create the review and stamp the listing's lastReviewedAt in one atomic
    // batch so reviewed listings float to the top of the lists. The bump is a
    // single-field, server-time-pinned write permitted by the rules.
    final batch = _db.batch();
    batch.set(reviewRef, data);
    batch.update(_bizRef(bizId), {
      "lastReviewedAt": FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  // -------------------- Helpers --------------------

  List<String> _sanitize(List<String> values, int max) {
    final seen = <String>{};
    final out = <String>[];
    for (final v in values) {
      final t = v.trim();
      if (t.isEmpty || t.length > 60) continue;
      if (seen.add(t.toLowerCase())) {
        out.add(t);
      }
      if (out.length >= max) break;
    }
    return out;
  }

  String _clampHours(String hours) {
    final t = hours.trim();
    return t.length > AirportBusiness.maxHoursLength
        ? t.substring(0, AirportBusiness.maxHoursLength)
        : t;
  }

  String _clampPhone(String phone) {
    final t = phone.trim();
    return t.length > AirportBusiness.maxPhoneLength
        ? t.substring(0, AirportBusiness.maxPhoneLength)
        : t;
  }

  String _clampFrequency(String freq) {
    final t = freq.trim();
    return t.length > AirportBusiness.maxFrequencyLength
        ? t.substring(0, AirportBusiness.maxFrequencyLength)
        : t;
  }
}
