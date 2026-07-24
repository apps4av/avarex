import 'package:cloud_firestore/cloud_firestore.dart';

enum ResourceType { aircraft, instructor }

ResourceType resourceTypeFromString(String? v) =>
    v == "instructor" ? ResourceType.instructor : ResourceType.aircraft;

String resourceTypeToString(ResourceType t) =>
    t == ResourceType.instructor ? "instructor" : "aircraft";

/// A schedulable resource owned by a scheduler group: an aircraft or a
/// flight instructor. Stored under schedulerGroups/{sgid}/resources/{rid}.
///
/// Aircraft may carry club-dispatch fields (hobbs/tach, MX due dates).
class SchedulableResource {
  final String id;
  final String name;
  final ResourceType type;
  final String? identifier; // tail number for aircraft, etc.
  final bool available; // false == out of service / unavailable (red)
  final DateTime createdAt;

  /// Current Hobbs meter reading (aircraft only).
  final double? hobbs;

  /// Current tach meter reading (aircraft only).
  final double? tach;

  /// Annual inspection due date.
  final DateTime? annualDue;

  /// Hobbs reading at which the next 100-hour inspection is due.
  final double? hundredHourDueHobbs;

  /// Transponder / ADS-B inspection due date.
  final DateTime? transponderDue;

  /// ELT battery / inspection due date.
  final DateTime? eltDue;

  /// Free-text MX notes (ADs, oil change, etc.).
  final String? mxNotes;

  const SchedulableResource({
    required this.id,
    required this.name,
    required this.type,
    this.identifier,
    this.available = true,
    required this.createdAt,
    this.hobbs,
    this.tach,
    this.annualDue,
    this.hundredHourDueHobbs,
    this.transponderDue,
    this.eltDue,
    this.mxNotes,
  });

  bool get isAircraft => type == ResourceType.aircraft;

  /// True when any calendar MX item is overdue or within [warnDays].
  bool mxDueSoon({int warnDays = 30}) {
    if (!isAircraft) return false;
    final now = DateTime.now();
    final warn = now.add(Duration(days: warnDays));
    bool due(DateTime? d) => d != null && !d.isAfter(warn);
    return due(annualDue) || due(transponderDue) || due(eltDue);
  }

  /// True when hobbs has reached or passed the 100-hour due meter.
  bool get hundredHourOverdue {
    if (hobbs == null || hundredHourDueHobbs == null) return false;
    return hobbs! >= hundredHourDueHobbs!;
  }

  /// True when the aircraft should not be dispatched (OOS, grounding MX).
  bool get needsAttention =>
      !available || mxDueSoon(warnDays: 0) || hundredHourOverdue;

  Map<String, dynamic> toMap() => {
        "name": name,
        "type": resourceTypeToString(type),
        "identifier": identifier,
        "available": available,
        "createdAt": Timestamp.fromDate(createdAt),
        "hobbs": hobbs,
        "tach": tach,
        "annualDue":
            annualDue == null ? null : Timestamp.fromDate(annualDue!),
        "hundredHourDueHobbs": hundredHourDueHobbs,
        "transponderDue": transponderDue == null
            ? null
            : Timestamp.fromDate(transponderDue!),
        "eltDue": eltDue == null ? null : Timestamp.fromDate(eltDue!),
        "mxNotes": mxNotes,
      };

  factory SchedulableResource.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data["createdAt"];
    DateTime? asDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    double? asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return null;
    }

    return SchedulableResource(
      id: doc.id,
      name: (data["name"] as String?) ?? "Resource",
      type: resourceTypeFromString(data["type"] as String?),
      identifier: data["identifier"] as String?,
      available: (data["available"] as bool?) ?? true,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      hobbs: asDouble(data["hobbs"]),
      tach: asDouble(data["tach"]),
      annualDue: asDate(data["annualDue"]),
      hundredHourDueHobbs: asDouble(data["hundredHourDueHobbs"]),
      transponderDue: asDate(data["transponderDue"]),
      eltDue: asDate(data["eltDue"]),
      mxNotes: data["mxNotes"] as String?,
    );
  }
}
