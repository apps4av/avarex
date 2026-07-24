import 'package:cloud_firestore/cloud_firestore.dart';

enum SquawkSeverity { grounding, caution, info }

enum SquawkStatus { open, resolved }

SquawkSeverity squawkSeverityFromString(String? v) {
  switch (v) {
    case "grounding":
      return SquawkSeverity.grounding;
    case "caution":
      return SquawkSeverity.caution;
    case "info":
    default:
      return SquawkSeverity.info;
  }
}

String squawkSeverityToString(SquawkSeverity s) {
  switch (s) {
    case SquawkSeverity.grounding:
      return "grounding";
    case SquawkSeverity.caution:
      return "caution";
    case SquawkSeverity.info:
      return "info";
  }
}

String squawkSeverityLabel(SquawkSeverity s) {
  switch (s) {
    case SquawkSeverity.grounding:
      return "Grounding";
    case SquawkSeverity.caution:
      return "Caution";
    case SquawkSeverity.info:
      return "Info";
  }
}

SquawkStatus squawkStatusFromString(String? v) =>
    v == "resolved" ? SquawkStatus.resolved : SquawkStatus.open;

String squawkStatusToString(SquawkStatus s) =>
    s == SquawkStatus.resolved ? "resolved" : "open";

/// A maintenance / discrepancy report on a club aircraft.
/// Stored under schedulerGroups/{sgid}/squawks/{sid}.
class Squawk {
  final String id;
  final String resourceId;
  final String resourceName;
  final String title;
  final String description;
  final SquawkSeverity severity;
  final SquawkStatus status;
  final String reportedByUid;
  final String reportedByName;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedByUid;
  final String? resolvedByName;

  const Squawk({
    required this.id,
    required this.resourceId,
    required this.resourceName,
    required this.title,
    required this.description,
    required this.severity,
    required this.status,
    required this.reportedByUid,
    required this.reportedByName,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedByUid,
    this.resolvedByName,
  });

  bool get isOpen => status == SquawkStatus.open;
  bool get isGrounding => severity == SquawkSeverity.grounding;

  Map<String, dynamic> toCreateMap() => {
        "resourceId": resourceId,
        "resourceName": resourceName,
        "title": title,
        "description": description,
        "severity": squawkSeverityToString(severity),
        "status": squawkStatusToString(status),
        "reportedByUid": reportedByUid,
        "reportedByName": reportedByName,
        "createdAt": Timestamp.fromDate(createdAt),
        "resolvedAt": null,
        "resolvedByUid": null,
        "resolvedByName": null,
      };

  factory Squawk.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final c = data["createdAt"];
    final r = data["resolvedAt"];
    return Squawk(
      id: doc.id,
      resourceId: (data["resourceId"] as String?) ?? "",
      resourceName: (data["resourceName"] as String?) ?? "",
      title: (data["title"] as String?) ?? "Squawk",
      description: (data["description"] as String?) ?? "",
      severity: squawkSeverityFromString(data["severity"] as String?),
      status: squawkStatusFromString(data["status"] as String?),
      reportedByUid: (data["reportedByUid"] as String?) ?? "",
      reportedByName: (data["reportedByName"] as String?) ?? "Pilot",
      createdAt: c is Timestamp ? c.toDate() : DateTime.now(),
      resolvedAt: r is Timestamp ? r.toDate() : null,
      resolvedByUid: data["resolvedByUid"] as String?,
      resolvedByName: data["resolvedByName"] as String?,
    );
  }
}
