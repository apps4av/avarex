import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/image_utils.dart';

class AircraftIconType {
  static const List<String> all = ["plane", "helicopter", "canard"];
}

/// The aircraft selected in the Aircraft & Performance dropdown: its display
/// name, the saved aircraft row of that name if any, and the built-in model of
/// that name if any. Both come from the same selection.
class SelectedAircraft {
  final String name;
  final Aircraft? saved;
  final AircraftPerformanceData? builtIn;

  const SelectedAircraft(this.name, this.saved, this.builtIn);

  /// Performance data used for landing distance. A saved aircraft with its own
  /// landing table uses that, otherwise the built-in model of the selection or
  /// of the saved aircraft's ICAO type.
  AircraftPerformanceData? get landingPerformance {
    final Aircraft? ac = saved;
    if (ac != null && ac.landingData.isNotEmpty) {
      try {
        final AircraftPerformanceData data = aircraftPerformanceDataFromAircraft(ac);
        if (data.rawLandingRollEntries != null || data.rawLanding50ftEntries != null) {
          return data;
        }
      } catch (_) {}
    }
    if (builtIn != null) {
      return builtIn;
    }
    if (ac != null && ac.type.trim().isNotEmpty) {
      return CommonAircraftData.getByIcao(ac.type.trim());
    }
    return null;
  }
}

class Aircraft {
  /// The aircraft chosen in the dropdown on the Aircraft & Performance screen.
  /// That dropdown is the single source of truth. When nothing was ever chosen
  /// the screen shows the Cessna 172SP, and so does this.
  static Future<SelectedAircraft> resolveSelected() async {
    String name = Storage().settings.getLastPerformanceAircraft().trim();
    if (name.isEmpty) {
      name = CommonAircraftData.cessna172sp.name;
    }
    Aircraft? saved;
    try {
      saved = await UserDatabaseHelper.db.getAircraft(name);
    } catch (_) {}
    AircraftPerformanceData? builtIn = CommonAircraftData.byName(name);
    if (saved == null && builtIn == null) {
      // The chosen aircraft was deleted. The screen falls back to the same one.
      name = CommonAircraftData.cessna172sp.name;
      builtIn = CommonAircraftData.cessna172sp;
    }
    return SelectedAircraft(name, saved, builtIn);
  }

  /// Loads [Storage.imagePlane] from the aircraft selected in the Performance
  /// dropdown when it is in `user.db`, otherwise from app setting
  /// `key-aircraft-icon`.
  static Future<void> reloadAircraftIcon() async {
    String iconType = Storage().settings.getAircraftIcon();
    final Aircraft? saved = (await resolveSelected()).saved;
    if (saved != null && saved.icon.isNotEmpty && AircraftIconType.all.contains(saved.icon)) {
      iconType = saved.icon;
    }
    Storage().imagePlane = await ImageUtils.loadImageFromAssets("$iconType.png");
    Storage().planeIconChange.value++;
  }

  /// The saved aircraft behind the Performance dropdown, if the selection is a
  /// saved aircraft and not a built-in model.
  static Future<Aircraft?> getActiveAircraft() async {
    return (await resolveSelected()).saved;
  }

  /// Best-glide speed in the app's current speed units. Prefers the dedicated
  /// field, then cruise TAS, then a typical light-GA value so the glide ring
  /// can still be drawn.
  double get bestGlideSpeed {
    final double? vg = double.tryParse(bestGlide);
    if (vg != null && vg > 0) {
      return vg;
    }
    final double? cruise = double.tryParse(cruiseTas);
    if (cruise != null && cruise > 0) {
      return cruise;
    }
    return 65.0;
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
  final String bestGlide;
  final String bestClimbSpeed;
  final String bestClimbRate;
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
    this.bestGlide = '',
    this.bestClimbSpeed = '',
    this.bestClimbRate = '',
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
      bestGlide: "",
      bestClimbSpeed: "",
      bestClimbRate: "",
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
      bestGlide: ((map['bestGlide'] ?? '') as String).toUpperCase(),
      bestClimbSpeed: ((map['bestClimbSpeed'] ?? '') as String).toUpperCase(),
      bestClimbRate: ((map['bestClimbRate'] ?? '') as String).toUpperCase(),
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
      'bestGlide': bestGlide.toUpperCase(),
      'bestClimbSpeed': bestClimbSpeed.toUpperCase(),
      'bestClimbRate': bestClimbRate.toUpperCase(),
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
    String? bestGlide,
    String? bestClimbSpeed,
    String? bestClimbRate,
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
      bestGlide: bestGlide ?? this.bestGlide,
      bestClimbSpeed: bestClimbSpeed ?? this.bestClimbSpeed,
      bestClimbRate: bestClimbRate ?? this.bestClimbRate,
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