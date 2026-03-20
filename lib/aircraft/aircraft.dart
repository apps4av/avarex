import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/image_utils.dart';

class AircraftIconType {
  static const List<String> all = ["plane", "helicopter", "canard"];
}

class Aircraft {
  static Future<void> reloadAircraftIcon() async {
    String iconType = Storage().settings.getAircraftIcon();
    Storage().imagePlane = await ImageUtils.loadImageFromAssets("$iconType.png");
  }

  // Basic identification
  final String tail;
  final String type;
  final String wake;
  final String icao;
  final String equipment;
  final String cruiseTas;
  final String surveillance;
  final String fuelEndurance;
  final String color;
  final String pic;
  final String picInfo;
  final String sinkRate;
  final String fuelBurn;
  final String base;
  final String other;
  final String icon;  // Aircraft icon: plane, helicopter, canard
  
  // Performance data (stored as JSON strings)
  final double maxGrossWeight;
  final double usableFuel;
  final double emptyWeight;
  final String takeoffData;  // JSON: {entries: [...], headwindPct, tailwindPct, softFieldPct}
  final String landingData;  // JSON: {entries: [...], headwindPct, tailwindPct, softFieldPct}
  final String cruiseData;   // JSON: cruise performance entries
  final String wnbData;      // JSON: weight & balance data (stations, envelope, limits)

  Aircraft({
    required this.tail,
    required this.type,
    required this.wake,
    required this.icao,
    required this.equipment,
    required this.cruiseTas,
    required this.surveillance,
    required this.fuelEndurance,
    required this.color,
    required this.pic,
    required this.picInfo,
    required this.sinkRate,
    required this.fuelBurn,
    required this.base,
    required this.other,
    this.icon = 'plane',
    this.maxGrossWeight = 0,
    this.usableFuel = 0,
    this.emptyWeight = 0,
    this.takeoffData = '',
    this.landingData = '',
    this.cruiseData = '',
    this.wnbData = '',
  });

  factory Aircraft.empty() {
    return Aircraft(
      tail: "",
      type: "",
      wake: "LIGHT",
      icao: "",
      equipment: "S",
      cruiseTas: "",
      surveillance: "N",
      fuelEndurance: "",
      color: "",
      pic: "",
      picInfo: "",
      sinkRate: "",
      fuelBurn: "",
      base: "",
      other: "",
    );
  }

  factory Aircraft.fromMap(Map<String, dynamic> map) {
    return Aircraft(
      tail: ((map['tail'] ?? '') as String).toUpperCase(),
      type: ((map['type'] ?? '') as String).toUpperCase(),
      wake: ((map['wake'] ?? 'LIGHT') as String).toUpperCase(),
      icao: ((map['icao'] ?? '') as String).toUpperCase(),
      equipment: ((map['equipment'] ?? 'S') as String).toUpperCase(),
      cruiseTas: ((map['cruiseTas'] ?? '') as String).toUpperCase(),
      surveillance: ((map['surveillance'] ?? 'N') as String).toUpperCase(),
      fuelEndurance: ((map['fuelEndurance'] ?? '') as String).toUpperCase(),
      color: ((map['color'] ?? '') as String).toUpperCase(),
      pic: ((map['pic'] ?? '') as String).toUpperCase(),
      picInfo: ((map['picInfo'] ?? '') as String).toUpperCase(),
      sinkRate: ((map['sinkRate'] ?? '') as String).toUpperCase(),
      fuelBurn: ((map['fuelBurn'] ?? '') as String).toUpperCase(),
      base: ((map['base'] ?? '') as String).toUpperCase(),
      other: ((map['other'] ?? '') as String).toUpperCase(),
      icon: (map['icon'] ?? 'plane') as String,
      maxGrossWeight: (map['maxGrossWeight'] ?? 0).toDouble(),
      usableFuel: (map['usableFuel'] ?? 0).toDouble(),
      emptyWeight: (map['emptyWeight'] ?? 0).toDouble(),
      takeoffData: (map['takeoffData'] ?? '') as String,
      landingData: (map['landingData'] ?? '') as String,
      cruiseData: (map['cruiseData'] ?? '') as String,
      wnbData: (map['wnbData'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tail': tail.toUpperCase(),
      'type': type.toUpperCase(),
      'wake': wake.toUpperCase(),
      'icao': icao.toUpperCase(),
      'equipment': equipment.toUpperCase(),
      'cruiseTas': cruiseTas.toUpperCase(),
      'surveillance': surveillance.toUpperCase(),
      'fuelEndurance': fuelEndurance.toUpperCase(),
      'color': color.toUpperCase(),
      'pic': pic.toUpperCase(),
      'picInfo': picInfo.toUpperCase(),
      'sinkRate': sinkRate.toUpperCase(),
      'fuelBurn': fuelBurn.toUpperCase(),
      'base': base.toUpperCase(),
      'other': other.toUpperCase(),
      'icon': icon,
      'maxGrossWeight': maxGrossWeight,
      'usableFuel': usableFuel,
      'emptyWeight': emptyWeight,
      'takeoffData': takeoffData,
      'landingData': landingData,
      'cruiseData': cruiseData,
      'wnbData': wnbData,
    };
  }
  
  /// Returns true if this aircraft has custom performance or saved W&B data
  bool get hasPerformanceData =>
      takeoffData.isNotEmpty || landingData.isNotEmpty || cruiseData.isNotEmpty || wnbData.isNotEmpty;
  
  /// Create a copy with updated fields
  Aircraft copyWith({
    String? tail,
    String? type,
    String? wake,
    String? icao,
    String? equipment,
    String? cruiseTas,
    String? surveillance,
    String? fuelEndurance,
    String? color,
    String? pic,
    String? picInfo,
    String? sinkRate,
    String? fuelBurn,
    String? base,
    String? other,
    String? icon,
    double? maxGrossWeight,
    double? usableFuel,
    double? emptyWeight,
    String? takeoffData,
    String? landingData,
    String? cruiseData,
    String? wnbData,
  }) {
    return Aircraft(
      tail: tail ?? this.tail,
      type: type ?? this.type,
      wake: wake ?? this.wake,
      icao: icao ?? this.icao,
      equipment: equipment ?? this.equipment,
      cruiseTas: cruiseTas ?? this.cruiseTas,
      surveillance: surveillance ?? this.surveillance,
      fuelEndurance: fuelEndurance ?? this.fuelEndurance,
      color: color ?? this.color,
      pic: pic ?? this.pic,
      picInfo: picInfo ?? this.picInfo,
      sinkRate: sinkRate ?? this.sinkRate,
      fuelBurn: fuelBurn ?? this.fuelBurn,
      base: base ?? this.base,
      other: other ?? this.other,
      icon: icon ?? this.icon,
      maxGrossWeight: maxGrossWeight ?? this.maxGrossWeight,
      usableFuel: usableFuel ?? this.usableFuel,
      emptyWeight: emptyWeight ?? this.emptyWeight,
      takeoffData: takeoffData ?? this.takeoffData,
      landingData: landingData ?? this.landingData,
      cruiseData: cruiseData ?? this.cruiseData,
      wnbData: wnbData ?? this.wnbData,
    );
  }
}