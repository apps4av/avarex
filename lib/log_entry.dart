class LogEntry {
  String id; // unique identifier (UUID, timestamp, etc.)
  DateTime date;

  // Aircraft information
  String aircraftMakeModel;   // e.g., C172S
  String aircraftIdentification; // registration / tail number (e.g., N123AB)
  String route;               // airports (e.g., KBOS-KJFK)

  // Times
  double totalFlightTime;     // total flight time (hours)
  double dayTime;             // day flight time
  double nightTime;           // night flight time
  double crossCountryTime;    // cross-country time
  double soloTime;            // solo time
  double simulatedInstruments;// simulated instrument (hood)
  double actualInstruments;   // actual instrument
  double dualReceived;        // instruction received
  double pilotInCommand;      // PIC time
  double copilot;             // SIC time
  double instructor;          // CFI time given
  double examiner;            // check airman time
  double flightSimulator;     // FTD/Simulator

  // Landings
  int dayLandings;
  int nightLandings;

  // Conditions
  double holdingProcedures;   // approaches / holds
  int instrumentApproaches;   // number of instrument approaches

  // Instructor details
  String instructorName;
  String instructorCertificate;

  // Remarks
  String remarks;

  LogEntry({
    required this.id,
    required this.date,
    required this.aircraftMakeModel,
    required this.aircraftIdentification,
    required this.route,
    this.totalFlightTime = 0.0,
    this.dayTime = 0.0,
    this.nightTime = 0.0,
    this.crossCountryTime = 0.0,
    this.soloTime = 0.0,
    this.simulatedInstruments = 0.0,
    this.actualInstruments = 0.0,
    this.dualReceived = 0.0,
    this.pilotInCommand = 0.0,
    this.copilot = 0.0,
    this.instructor = 0.0,
    this.examiner = 0.0,
    this.flightSimulator = 0.0,
    this.dayLandings = 0,
    this.nightLandings = 0,
    this.holdingProcedures = 0.0,
    this.instrumentApproaches = 0,
    this.instructorName = '',
    this.instructorCertificate = '',
    this.remarks = '',
  });

  factory LogEntry.fromMap(Map<String, dynamic> map) => LogEntry(
    id: map['id'] as String,
    date: DateTime.parse(map['date'] as String),
    aircraftMakeModel: map['aircraftMakeModel'] as String,
    aircraftIdentification: map['aircraftIdentification'] as String,
    route: map['route'] as String,
    totalFlightTime: (map['totalFlightTime'] as num).toDouble(),
    dayTime: (map['dayTime'] as num).toDouble(),
    nightTime: (map['nightTime'] as num).toDouble(),
    crossCountryTime: (map['crossCountryTime'] as num).toDouble(),
    soloTime: (map['soloTime'] as num).toDouble(),
    simulatedInstruments: (map['simulatedInstruments'] as num).toDouble(),
    actualInstruments: (map['actualInstruments'] as num).toDouble(),
    dualReceived: (map['dualReceived'] as num).toDouble(),
    pilotInCommand: (map['pilotInCommand'] as num).toDouble(),
    copilot: (map['copilot'] as num).toDouble(),
    instructor: (map['instructor'] as num).toDouble(),
    examiner: (map['examiner'] as num).toDouble(),
    flightSimulator: (map['flightSimulator'] as num).toDouble(),
    dayLandings: map['dayLandings'] as int,
    nightLandings: map['nightLandings'] as int,
    holdingProcedures: (map['holdingProcedures'] as num).toDouble(),
    instrumentApproaches: map['instrumentApproaches'] as int,
    instructorName: map['instructorName'] as String,
    instructorCertificate: map['instructorCertificate'] as String,
    remarks: map['remarks'] as String,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date.toIso8601String(),
    'aircraftMakeModel': aircraftMakeModel,
    'aircraftIdentification': aircraftIdentification,
    'route': route,
    'totalFlightTime': totalFlightTime,
    'dayTime': dayTime,
    'nightTime': nightTime,
    'crossCountryTime': crossCountryTime,
    'soloTime': soloTime,
    'simulatedInstruments': simulatedInstruments,
    'actualInstruments': actualInstruments,
    'dualReceived': dualReceived,
    'pilotInCommand': pilotInCommand,
    'copilot': copilot,
    'instructor': instructor,
    'examiner': examiner,
    'flightSimulator': flightSimulator,
    'dayLandings': dayLandings,
    'nightLandings': nightLandings,
    'holdingProcedures': holdingProcedures,
    'instrumentApproaches': instrumentApproaches,
    'instructorName': instructorName,
    'instructorCertificate': instructorCertificate,
    'remarks': remarks,
  };
}
