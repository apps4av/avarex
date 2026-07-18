import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// A crowd-sourced business/FBO listing tied to an airport.
///
/// Business *names* are seeded by an offline import script; every other
/// column (services, fuel, hours, reviews) is filled in by signed-in users
/// from inside the app. Entries can never be deleted, and each carries the
/// contributor's name so nothing is left anonymously.
///
/// Firestore layout:
///   airportBusinesses/{bizId}                 -> AirportBusiness
///   airportBusinesses/{bizId}/reviews/{rid}   -> BusinessReview
class AirportBusiness {
  /// Common fuel types offered to select from when contributing.
  static const List<String> fuelOptions = [
    "100LL",
    "Jet A",
    "Jet A+",
    "MOGAS",
    "Sustainable Aviation Fuel",
    "UL94",
  ];

  /// Common service categories offered to select from when contributing.
  static const List<String> serviceOptions = [
    "Fuel",
    "Self-Service Fuel",
    "Flight Training",
    "Aircraft Maintenance",
    "Avionics",
    "Aircraft Rental",
    "Charter",
    "Hangar / Tie-Down",
    "Courtesy Car",
    "Car Rental",
    "Catering",
    "Oxygen / Nitrogen",
    "De-Ice",
    "Pilot Lounge",
    "WiFi",
  ];

  static const int maxServices = 30;
  static const int maxFuelTypes = 10;
  static const int maxFuelPrices = 12;
  static const int maxHoursLength = 200;
  static const int maxNameLength = 120;
  static const int maxPhoneLength = 30;
  static const int maxFrequencyLength = 30;

  final String id;
  final String airport; // uppercase LocationID / FAA id, e.g. "KBED"
  final String name;
  final List<String> services;
  final List<String> fuelTypes;
  // Crowd-sourced price per fuel type (e.g. "100LL" -> 6.49), each carrying
  // the date it was last set. Empty until a pilot enters prices.
  final Map<String, FuelPrice> fuelPrices;
  final String operatingHours;
  final String phoneNumber;
  final String radioFrequency;
  final String createdByUid;
  final String createdByName;
  final String source; // "user" (added in-app) or an import source
  final DateTime createdAt;
  // Attribution for the most recent detail edit (null until first edited).
  final String? lastEditedByName;
  final DateTime? updatedAt;
  // Server time of the most recent review posted against this listing (null
  // until first reviewed). Stamped on the listing when a review is created so
  // reviewed listings can be floated to the top without counting the reviews
  // subcollection on read.
  final DateTime? lastReviewedAt;
  // Physical location on the field (null for user-added listings that were
  // created without a coordinate; seeded listings carry it).
  final double? latitude;
  final double? longitude;

  const AirportBusiness({
    required this.id,
    required this.airport,
    required this.name,
    this.services = const [],
    this.fuelTypes = const [],
    this.fuelPrices = const {},
    this.operatingHours = "",
    this.phoneNumber = "",
    this.radioFrequency = "",
    required this.createdByUid,
    required this.createdByName,
    this.source = "user",
    required this.createdAt,
    this.lastEditedByName,
    this.updatedAt,
    this.lastReviewedAt,
    this.latitude,
    this.longitude,
  });

  /// Whether this listing has a usable map coordinate.
  bool get hasLocation => latitude != null && longitude != null;

  /// The listing's coordinate. Only valid when [hasLocation] is true.
  LatLng get coordinate => LatLng(latitude!, longitude!);

  /// Whether a real pilot has created, modified or reviewed this listing, as
  /// opposed to an untouched seeded/import entry. Derived entirely from
  /// persisted Firestore fields: `source` ("user" when created in-app),
  /// `updatedAt` (set on a detail edit) and `lastReviewedAt` (set when a
  /// review is posted), so the signal is shared across all users, not local
  /// device state.
  bool get hasUserActivity =>
      source == "user" || updatedAt != null || lastReviewedAt != null;

  /// Timestamp of the most recent user interaction (latest of: detail edit,
  /// review posted, or creation time for user-created listings), or null for
  /// untouched seeded listings. Used to float interacted listings to the top.
  DateTime? get userActivityAt {
    DateTime? latest;
    void consider(DateTime? d) {
      if (d != null && (latest == null || d.isAfter(latest!))) latest = d;
    }

    consider(updatedAt);
    consider(lastReviewedAt);
    if (source == "user") consider(createdAt);
    return latest;
  }

  /// Ordering used by the businesses lists: listings a pilot has created or
  /// modified come first (most recently touched first); everything else falls
  /// back to alphabetical by name.
  static int compareInteractedFirst(AirportBusiness a, AirportBusiness b) {
    if (a.hasUserActivity != b.hasUserActivity) {
      return a.hasUserActivity ? -1 : 1;
    }
    if (a.hasUserActivity && b.hasUserActivity) {
      final c = b.userActivityAt!.compareTo(a.userActivityAt!);
      if (c != 0) return c;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Squared planar distance from [origin] to this listing (cheap ordering
  /// metric; no need for a real great-circle distance just to sort). Uses the
  /// same equirectangular approximation the old offline FBO list used. Null
  /// when this listing has no coordinate.
  double? distanceSqTo(LatLng origin) {
    if (!hasLocation) return null;
    final corr = pow(cos(origin.latitude * pi / 180.0), 2).toDouble();
    final dLon = longitude! - origin.longitude;
    final dLat = latitude! - origin.latitude;
    return dLon * dLon * corr + dLat * dLat;
  }

  /// Ordering used by the businesses lists once an airport [origin] is known:
  /// pilot-interacted listings still come first (most recently touched first),
  /// then everything else is ordered nearest-first from the airport (matching
  /// the old offline FBO list, where distance ordering kept far/noisy Google
  /// Places results out of the way). Listings without a coordinate sort last,
  /// then alphabetically. Falls back to [compareInteractedFirst] when [origin]
  /// is null.
  static Comparator<AirportBusiness> byDistanceInteractedFirst(
      LatLng? origin) {
    if (origin == null) return compareInteractedFirst;
    return (a, b) {
      if (a.hasUserActivity != b.hasUserActivity) {
        return a.hasUserActivity ? -1 : 1;
      }
      if (a.hasUserActivity && b.hasUserActivity) {
        final c = b.userActivityAt!.compareTo(a.userActivityAt!);
        if (c != 0) return c;
      }
      final da = a.distanceSqTo(origin);
      final db = b.distanceSqTo(origin);
      if (da != null && db != null) {
        final c = da.compareTo(db);
        if (c != 0) return c;
      } else if (da != null) {
        return -1; // a has a location, b doesn't -> a first
      } else if (db != null) {
        return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    };
  }

  Map<String, dynamic> toCreateMap() {
    final map = <String, dynamic>{
      "airport": airport.toUpperCase(),
      "name": name.trim(),
      "nameLower": name.trim().toLowerCase(),
      "services": services,
      "fuelTypes": fuelTypes,
      "operatingHours": operatingHours.trim(),
      "phoneNumber": phoneNumber.trim(),
      "radioFrequency": radioFrequency.trim(),
      "createdByUid": createdByUid,
      "createdByName": createdByName,
      "source": source,
      "createdAt": Timestamp.fromDate(createdAt),
    };
    // Only include location when present, so user-added listings without a
    // coordinate don't write null fields (and stay within the rules).
    if (latitude != null && longitude != null) {
      map["latitude"] = latitude;
      map["longitude"] = longitude;
    }
    return map;
  }

  factory AirportBusiness.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final created = data["createdAt"];
    final updated = data["updatedAt"];
    return AirportBusiness(
      id: doc.id,
      airport: (data["airport"] as String?) ?? "",
      name: (data["name"] as String?) ?? "",
      services: List<String>.from((data["services"] as List?) ?? const []),
      fuelTypes: List<String>.from((data["fuelTypes"] as List?) ?? const []),
      fuelPrices: _readFuelPrices(data["fuelPrices"]),
      operatingHours: (data["operatingHours"] as String?) ?? "",
      phoneNumber: (data["phoneNumber"] as String?) ?? "",
      radioFrequency: (data["radioFrequency"] as String?) ?? "",
      createdByUid: (data["createdByUid"] as String?) ?? "",
      createdByName: (data["createdByName"] as String?) ?? "Unknown",
      source: (data["source"] as String?) ?? "user",
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
      lastEditedByName: data["lastEditedByName"] as String?,
      updatedAt: updated is Timestamp ? updated.toDate() : null,
      lastReviewedAt:
          data["lastReviewedAt"] is Timestamp ? (data["lastReviewedAt"] as Timestamp).toDate() : null,
      latitude: _readDouble(data["latitude"]),
      longitude: _readDouble(data["longitude"]),
    );
  }

  static double? _readDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static Map<String, FuelPrice> _readFuelPrices(Object? v) {
    if (v is! Map) return const {};
    final out = <String, FuelPrice>{};
    v.forEach((key, val) {
      if (key is String && val is Map) {
        final price = _readDouble(val["price"]);
        if (price != null) {
          final ts = val["updatedAt"];
          out[key] = FuelPrice(
            price: price,
            updatedAt: ts is Timestamp ? ts.toDate() : null,
          );
        }
      }
    });
    return out;
  }
}

/// A single fuel price plus the date it was last set.
class FuelPrice {
  final double price;
  // Null only briefly while a just-written server timestamp resolves.
  final DateTime? updatedAt;

  const FuelPrice({required this.price, this.updatedAt});
}

/// Review aggregates for a business, computed on demand from the reviews
/// subcollection (Firestore aggregation query) rather than stored on the
/// listing document. Keeping this off the document means the average rating
/// cannot be forged -- it always reflects real review documents.
class BusinessStats {
  final int reviewCount;
  final double averageRating; // 0..5, 0 when there are no reviews

  const BusinessStats({required this.reviewCount, required this.averageRating});

  static const BusinessStats empty =
      BusinessStats(reviewCount: 0, averageRating: 0);

  bool get hasReviews => reviewCount > 0;

  /// Build from an in-memory list of ratings (used where reviews are already
  /// loaded, e.g. the detail screen's live stream).
  factory BusinessStats.fromRatings(Iterable<int> ratings) {
    var count = 0;
    var sum = 0;
    for (final r in ratings) {
      count++;
      sum += r;
    }
    return BusinessStats(
      reviewCount: count,
      averageRating: count == 0 ? 0 : sum / count,
    );
  }
}
