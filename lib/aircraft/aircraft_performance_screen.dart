import 'dart:convert';
import 'package:avaremp/aircraft/aircraft.dart';
import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class AircraftPerformanceScreen extends StatefulWidget {
  const AircraftPerformanceScreen({super.key});

  @override
  State<AircraftPerformanceScreen> createState() => _AircraftPerformanceScreenState();
}

class _TakeoffLandingEntry {
  double altitude;
  double temp;
  double weight;
  double groundRoll;
  double over50ft;
  
  _TakeoffLandingEntry({
    this.altitude = 0, 
    this.temp = 15, 
    this.weight = 2400, 
    this.groundRoll = 0,
    this.over50ft = 0,
  });
  
  Map<String, dynamic> toMap() => {
    'altitude': altitude, 
    'temp': temp, 
    'weight': weight, 
    'groundRoll': groundRoll,
    'over50ft': over50ft,
  };
  
  factory _TakeoffLandingEntry.fromMap(Map<String, dynamic> map) {
    return _TakeoffLandingEntry(
      altitude: (map['altitude'] ?? 0).toDouble(),
      temp: (map['temp'] ?? 15).toDouble(),
      weight: (map['weight'] ?? 2400).toDouble(),
      groundRoll: (map['groundRoll'] ?? map['value'] ?? 0).toDouble(),
      over50ft: (map['over50ft'] ?? 0).toDouble(),
    );
  }
}

class _CruiseEntry {
  int altitude;
  int temp;
  int powerPercent;
  double ktas;
  double gph;
  
  _CruiseEntry({this.altitude = 8000, this.temp = 0, this.powerPercent = 65, this.ktas = 110, this.gph = 8.5});
  
  Map<String, dynamic> toMap() => {'altitude': altitude, 'temp': temp, 'powerPercent': powerPercent, 'ktas': ktas, 'gph': gph};
  
  factory _CruiseEntry.fromMap(Map<String, dynamic> map) {
    return _CruiseEntry(
      altitude: (map['altitude'] ?? 8000).toInt(),
      temp: (map['temp'] ?? 0).toInt(),
      powerPercent: (map['powerPercent'] ?? 65).toInt(),
      ktas: (map['ktas'] ?? 110).toDouble(),
      gph: (map['gph'] ?? 8.5).toDouble(),
    );
  }
}

class _WnbStation {
  String name;
  double arm;
  double weight;
  
  _WnbStation({this.name = '', this.arm = 0, this.weight = 0});
  
  double get moment => weight * arm;
  
  Map<String, dynamic> toMap() => {'name': name, 'arm': arm, 'weight': weight};
}

class _AircraftPerformanceScreenState extends State<AircraftPerformanceScreen> {
  AircraftPerformanceData _selectedAircraft = CommonAircraftData.cessna172sp;

  // Takeoff inputs
  final _takeoffPressureAltController = TextEditingController(text: '0');
  final _takeoffTempController = TextEditingController(text: '15');
  final _takeoffWeightController = TextEditingController(text: '2400');
  final _takeoffHeadwindController = TextEditingController(text: '0');
  bool _takeoffSoftField = false;

  // Landing inputs
  final _landingPressureAltController = TextEditingController(text: '0');
  final _landingTempController = TextEditingController(text: '15');
  final _landingWeightController = TextEditingController(text: '2200');
  final _landingHeadwindController = TextEditingController(text: '0');
  bool _landingSoftField = false;

  // Cruise inputs
  final _cruiseAltitudeController = TextEditingController(text: '8000');
  final _cruiseTempController = TextEditingController(text: '0');
  int _cruisePowerPercent = 65;

  // Fuel inputs
  final _fuelDistanceController = TextEditingController(text: '200');
  final _fuelGroundSpeedController = TextEditingController(text: '110');
  final _fuelFlowController = TextEditingController(text: '8.5');
  final _fuelReserveController = TextEditingController(text: '45');
  final _fuelTaxiController = TextEditingController(text: '1.0');

  // Custom aircraft inputs
  bool _showCustomEntry = false;
  final _customNameController = TextEditingController();
  final _customIcaoController = TextEditingController();
  final _customMaxWeightController = TextEditingController(text: '2400');
  final _customUsableFuelController = TextEditingController(text: '48');
  final _customEmptyWeightController = TextEditingController(text: '1500');
  final _customToHeadwindController = TextEditingController(text: '1.5');
  final _customToTailwindController = TextEditingController(text: '10.0');
  final _customToSoftFieldController = TextEditingController(text: '15');
  final _customLdHeadwindController = TextEditingController(text: '1.5');
  final _customLdTailwindController = TextEditingController(text: '10.0');
  final _customLdSoftFieldController = TextEditingController(text: '20');
  
  // Aircraft identification fields
  String _customWake = 'LIGHT';
  String _customIcon = 'plane';
  final _customColorController = TextEditingController();
  final _customModeSController = TextEditingController();
  final _customPicController = TextEditingController();
  final _customPicInfoController = TextEditingController();
  final _customBaseController = TextEditingController();
  final _customEquipmentController = TextEditingController(text: 'S');
  final _customSurveillanceController = TextEditingController(text: 'N');
  final _customOtherController = TextEditingController();
  final _customCruiseTasController = TextEditingController();
  final _customFuelEnduranceController = TextEditingController();
  final _customSinkRateController = TextEditingController();
  
  // Dynamic POH entries (combined tables)
  List<_TakeoffLandingEntry> _customTakeoffEntries = [];
  List<_TakeoffLandingEntry> _customLandingEntries = [];
  List<_CruiseEntry> _customCruiseEntries = [];

  List<AircraftPerformanceData> _customAircraft = [];

  // W&B data
  List<_WnbStation> _wnbStations = [];
  List<Offset> _wnbEnvelopePoints = [];
  double _wnbMinArm = 35;
  double _wnbMaxArm = 50;
  double _wnbMinWeight = 1000;
  double _wnbMaxWeight = 2800;
  bool _wnbEditing = false;

  // Page navigation
  int _pageIndex = 0;
  static const List<String> _pageLabels = ['Takeoff', 'Landing', 'Cruise', 'Fuel', 'W&B', 'Custom'];

  @override
  void initState() {
    super.initState();
    _takeoffWeightController.text = _selectedAircraft.maxGrossWeight.toStringAsFixed(0);
    _loadCustomAircraft();
    _initializeDefaultEntries();
    _loadWnbForAircraft();
  }

  void _initializeDefaultEntries() {
    _customTakeoffEntries = [
      _TakeoffLandingEntry(altitude: 0, temp: 15, weight: 2400, groundRoll: 900, over50ft: 1500),
      _TakeoffLandingEntry(altitude: 0, temp: 15, weight: 2100, groundRoll: 720, over50ft: 1200),
      _TakeoffLandingEntry(altitude: 4000, temp: 15, weight: 2400, groundRoll: 1200, over50ft: 2100),
      _TakeoffLandingEntry(altitude: 4000, temp: 15, weight: 2100, groundRoll: 960, over50ft: 1700),
    ];
    _customLandingEntries = [
      _TakeoffLandingEntry(altitude: 0, temp: 15, weight: 2400, groundRoll: 550, over50ft: 1300),
      _TakeoffLandingEntry(altitude: 0, temp: 15, weight: 2100, groundRoll: 495, over50ft: 1170),
      _TakeoffLandingEntry(altitude: 4000, temp: 15, weight: 2400, groundRoll: 650, over50ft: 1500),
      _TakeoffLandingEntry(altitude: 4000, temp: 15, weight: 2100, groundRoll: 585, over50ft: 1350),
    ];
    _customCruiseEntries = [
      _CruiseEntry(altitude: 4000, temp: 0, powerPercent: 65, ktas: 118, gph: 8.8),
      _CruiseEntry(altitude: 8000, temp: 0, powerPercent: 55, ktas: 105, gph: 7.2),
      _CruiseEntry(altitude: 8000, temp: 0, powerPercent: 65, ktas: 116, gph: 8.6),
      _CruiseEntry(altitude: 8000, temp: 0, powerPercent: 75, ktas: 124, gph: 10.1),
      _CruiseEntry(altitude: 8000, temp: 20, powerPercent: 65, ktas: 118, gph: 8.4),
      _CruiseEntry(altitude: 12000, temp: 0, powerPercent: 65, ktas: 117, gph: 7.9),
    ];
  }

  void _loadWnbForAircraft() async {
    WnbData? wnbData;
    
    // For predefined aircraft, always use POH data (not database)
    wnbData = CommonWnbData.getWnbData(_selectedAircraft.name);
    
    // For custom aircraft, try to get from database
    if (wnbData == null) {
      try {
        Aircraft aircraft = await UserDatabaseHelper.db.getAircraft(_selectedAircraft.name);
        if (aircraft.wnbData.isNotEmpty) {
          wnbData = WnbData.fromJson(aircraft.wnbData);
        }
      } catch (e) {
        // Not in database
      }
    }
    
    // If still null, use defaults
    wnbData ??= WnbData.defaultData();
    
    setState(() {
      _wnbStations = wnbData!.stations.map((s) => _WnbStation(name: s.name, arm: s.arm, weight: s.defaultWeight)).toList();
      _wnbEnvelopePoints = List<Offset>.from(wnbData.envelopePoints);
      _wnbMinArm = wnbData.minArm;
      _wnbMaxArm = wnbData.maxArm;
      _wnbMinWeight = wnbData.minWeight;
      _wnbMaxWeight = wnbData.maxWeight;
      // Reset editing state when switching aircraft (especially for predefined)
      _wnbEditing = false;
    });
  }

  Offset _calculateCG() {
    double totalWeight = 0;
    double totalMoment = 0;
    for (var station in _wnbStations) {
      totalWeight += station.weight;
      totalMoment += station.moment;
    }
    if (totalWeight == 0) return const Offset(0, 0);
    return Offset(totalMoment / totalWeight, totalWeight);
  }

  bool _isCGWithinLimits() {
    if (_wnbEnvelopePoints.length < 3) return false;
    Offset cg = _calculateCG();
    return _isPointInPolygon(cg.dx, cg.dy, _wnbEnvelopePoints);
  }
  
  bool _isPointInPolygon(double x, double y, List<Offset> polygon) {
    int n = polygon.length;
    bool inside = false;
    
    for (int i = 0, j = n - 1; i < n; j = i++) {
      double xi = polygon[i].dx, yi = polygon[i].dy;
      double xj = polygon[j].dx, yj = polygon[j].dy;
      
      if (((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    
    return inside;
  }

  bool _isCustomAircraft() {
    return _customAircraft.any((a) => a.name == _selectedAircraft.name);
  }

  void _populateFromSelectedAircraft() async {
    AircraftPerformanceData a = _selectedAircraft;
    
    _customNameController.text = a.name;
    _customIcaoController.text = a.icaoType;
    _customMaxWeightController.text = a.maxGrossWeight.toStringAsFixed(0);
    _customUsableFuelController.text = a.usableFuel.toStringAsFixed(0);
    _customEmptyWeightController.text = a.emptyWeight.toStringAsFixed(0);
    _customToHeadwindController.text = a.takeoffHeadwindPct.toStringAsFixed(1);
    _customToTailwindController.text = a.takeoffTailwindPct.toStringAsFixed(1);
    _customToSoftFieldController.text = a.takeoffSoftFieldPct.toStringAsFixed(0);
    _customLdHeadwindController.text = a.landingHeadwindPct.toStringAsFixed(1);
    _customLdTailwindController.text = a.landingTailwindPct.toStringAsFixed(1);
    _customLdSoftFieldController.text = a.landingSoftFieldPct.toStringAsFixed(0);
    
    // Try to load full aircraft data from database
    try {
      Aircraft aircraft = await UserDatabaseHelper.db.getAircraft(a.name);
      _customWake = aircraft.wake.isNotEmpty ? aircraft.wake : 'LIGHT';
      _customIcon = aircraft.icon.isNotEmpty ? aircraft.icon : 'plane';
      _customColorController.text = aircraft.color;
      _customModeSController.text = aircraft.icao;
      _customPicController.text = aircraft.pic;
      _customPicInfoController.text = aircraft.picInfo;
      _customBaseController.text = aircraft.base;
      _customEquipmentController.text = aircraft.equipment.isNotEmpty ? aircraft.equipment : 'S';
      _customSurveillanceController.text = aircraft.surveillance.isNotEmpty ? aircraft.surveillance : 'N';
      _customOtherController.text = aircraft.other;
      _customCruiseTasController.text = aircraft.cruiseTas;
      _customFuelEnduranceController.text = aircraft.fuelEndurance;
      _customSinkRateController.text = aircraft.sinkRate;
    } catch (e) {
      // Aircraft not in database (predefined), use defaults
      _customWake = 'LIGHT';
      _customIcon = 'plane';
      _customColorController.clear();
      _customModeSController.clear();
      _customPicController.clear();
      _customPicInfoController.clear();
      _customBaseController.clear();
      _customEquipmentController.text = 'S';
      _customSurveillanceController.text = 'N';
      _customOtherController.clear();
      _customCruiseTasController.clear();
      _customFuelEnduranceController.clear();
      _customSinkRateController.clear();
    }

    if (a.hasRawEntries) {
      _customTakeoffEntries = _convertRawToEntries(
        a.rawTakeoffRollEntries ?? [], a.rawTakeoff50ftEntries ?? []);
      _customLandingEntries = _convertRawToEntries(
        a.rawLandingRollEntries ?? [], a.rawLanding50ftEntries ?? []);
      _customCruiseEntries = _convertRawCruiseToEntries(a.rawCruiseEntries ?? []);
    } else {
      _customTakeoffEntries = _extractPerformanceEntries(
        a.takeoffGroundRoll, a.takeoffOver50ft, a.maxGrossWeight);
      _customLandingEntries = _extractPerformanceEntries(
        a.landingGroundRoll, a.landingOver50ft, a.maxGrossWeight);
      _customCruiseEntries = _extractCruiseEntries(a.cruiseTable);
    }
    
    setState(() {});
  }

  List<_TakeoffLandingEntry> _convertRawToEntries(
      List<Performance3DEntry> rollEntries, List<Performance3DEntry> over50Entries) {
    List<_TakeoffLandingEntry> entries = [];
    for (var roll in rollEntries) {
      Performance3DEntry? matching = over50Entries.cast<Performance3DEntry?>().firstWhere(
        (e) => e!.altitude == roll.altitude && e.temp == roll.temp && e.weight == roll.weight,
        orElse: () => null,
      );
      entries.add(_TakeoffLandingEntry(
        altitude: roll.altitude,
        temp: roll.temp,
        weight: roll.weight,
        groundRoll: roll.value,
        over50ft: matching?.value ?? roll.value * 1.5,
      ));
    }
    return entries;
  }

  List<_CruiseEntry> _convertRawCruiseToEntries(List<Cruise3DEntry> rawEntries) {
    return rawEntries.map((e) => _CruiseEntry(
      altitude: e.altitude.toInt(),
      temp: e.temp.toInt(),
      powerPercent: e.powerPercent.toInt(),
      ktas: e.ktas,
      gph: e.gph,
    )).toList();
  }

  List<_TakeoffLandingEntry> _extractPerformanceEntries(
      PerformanceTable rollTable, PerformanceTable over50Table, double maxWeight) {
    List<_TakeoffLandingEntry> entries = [];
    
    List<double> alts = rollTable.pressureAltitudes;
    List<double> temps = rollTable.temperatures;
    
    List<int> altIndices = _selectIndices(alts.length, 4);
    List<int> tempIndices = _selectIndices(temps.length, 3);
    
    for (int ai in altIndices) {
      for (int ti in tempIndices) {
        double alt = alts[ai];
        double temp = temps[ti];
        double roll = rollTable.values[ai][ti];
        double over50 = over50Table.values[ai][ti];
        
        entries.add(_TakeoffLandingEntry(
          altitude: alt,
          temp: temp,
          weight: maxWeight,
          groundRoll: roll,
          over50ft: over50,
        ));
      }
    }
    
    return entries;
  }

  List<int> _selectIndices(int length, int count) {
    if (length <= count) {
      return List.generate(length, (i) => i);
    }
    List<int> indices = [];
    for (int i = 0; i < count; i++) {
      indices.add((i * (length - 1) / (count - 1)).round());
    }
    return indices.toSet().toList()..sort();
  }

  List<_CruiseEntry> _extractCruiseEntries(CruisePerformanceTable table) {
    List<_CruiseEntry> entries = [];
    
    Set<int> altitudes = table.entries.map((e) => e.altitude).toSet();
    List<int> sortedAlts = altitudes.toList()..sort();
    List<int> selectedAlts = sortedAlts.length <= 4 
        ? sortedAlts 
        : _selectIndices(sortedAlts.length, 4).map((i) => sortedAlts[i]).toList();
    
    for (int alt in selectedAlts) {
      List<CruiseTableEntry> atAlt = table.entries.where((e) => e.altitude == alt).toList();
      atAlt.sort((a, b) => b.percentPower.compareTo(a.percentPower));
      
      List<CruiseTableEntry> selected = atAlt.length <= 3 
          ? atAlt 
          : _selectIndices(atAlt.length, 3).map((i) => atAlt[i]).toList();
      
      for (var e in selected) {
        entries.add(_CruiseEntry(
          altitude: e.altitude,
          temp: e.temp,
          powerPercent: e.percentPower,
          ktas: e.ktas,
          gph: e.gph,
        ));
      }
    }
    
    return entries;
  }

  Future<void> _loadCustomAircraft() async {
    // Load aircraft from database that have performance data
    List<Aircraft> dbAircraft = await UserDatabaseHelper.db.getAllAircraft();
    _customAircraft = dbAircraft
        .where((a) => a.hasPerformanceData)
        .map((a) => _aircraftToPerformanceData(a))
        .toList();

    // Also load legacy custom aircraft from settings (for migration)
    await _migrateLegacyCustomAircraft();
    
    // Load last used aircraft
    await _loadSelectedAircraft();
    
    setState(() {
      _ensureSelectedAircraftInList();
      _takeoffWeightController.text = _selectedAircraft.maxGrossWeight.toStringAsFixed(0);
      _landingWeightController.text = (_selectedAircraft.maxGrossWeight * 0.9).toStringAsFixed(0);
      CruiseResult cruise = _selectedAircraft.getCruisePerformance(8000, 65);
      _fuelFlowController.text = cruise.gph.toStringAsFixed(1);
    });
  }
  
  Future<void> _migrateLegacyCustomAircraft() async {
    String? data = await _getCustomAircraftData();
    if (data != null && data.isNotEmpty) {
      try {
        List<dynamic> list = jsonDecode(data);
        for (var e in list) {
          AircraftPerformanceData perfData = _customAircraftFromMap(e);
          // Save to aircraft database
          Aircraft aircraft = _performanceDataToAircraft(perfData, e);
          await UserDatabaseHelper.db.addAircraft(aircraft);
          if (!_customAircraft.any((a) => a.name == perfData.name)) {
            _customAircraft.add(perfData);
          }
        }
        // Clear legacy data after migration
        await UserDatabaseHelper.db.insertSetting('customAircraftPerformance', '');
      } catch (e) {
        // ignore migration errors
      }
    }
  }
  
  AircraftPerformanceData _aircraftToPerformanceData(Aircraft aircraft) {
    List<_TakeoffLandingEntry> takeoffEntries = [];
    List<_TakeoffLandingEntry> landingEntries = [];
    List<_CruiseEntry> cruiseEntries = [];
    double toHeadwindPct = 1.5, toTailwindPct = 10.0, toSoftFieldPct = 15.0;
    double ldHeadwindPct = 1.5, ldTailwindPct = 10.0, ldSoftFieldPct = 20.0;
    
    if (aircraft.takeoffData.isNotEmpty) {
      try {
        Map<String, dynamic> decoded = jsonDecode(aircraft.takeoffData);
        List<dynamic> list = decoded['entries'] ?? [];
        takeoffEntries = list.map((e) => _TakeoffLandingEntry.fromMap(e)).toList();
        toHeadwindPct = (decoded['headwindPct'] ?? 1.5).toDouble();
        toTailwindPct = (decoded['tailwindPct'] ?? 10.0).toDouble();
        toSoftFieldPct = (decoded['softFieldPct'] ?? 15.0).toDouble();
      } catch (e) { /* ignore */ }
    }
    
    if (aircraft.landingData.isNotEmpty) {
      try {
        Map<String, dynamic> decoded = jsonDecode(aircraft.landingData);
        List<dynamic> list = decoded['entries'] ?? [];
        landingEntries = list.map((e) => _TakeoffLandingEntry.fromMap(e)).toList();
        ldHeadwindPct = (decoded['headwindPct'] ?? 1.5).toDouble();
        ldTailwindPct = (decoded['tailwindPct'] ?? 10.0).toDouble();
        ldSoftFieldPct = (decoded['softFieldPct'] ?? 20.0).toDouble();
      } catch (e) { /* ignore */ }
    }
    
    if (aircraft.cruiseData.isNotEmpty) {
      try {
        List<dynamic> list = jsonDecode(aircraft.cruiseData);
        cruiseEntries = list.map((e) => _CruiseEntry.fromMap(e)).toList();
      } catch (e) { /* ignore */ }
    }
    
    List<Performance3DEntry> rawToRoll = takeoffEntries.map((e) => Performance3DEntry(
      altitude: e.altitude, temp: e.temp, weight: e.weight, value: e.groundRoll,
    )).toList();
    
    List<Performance3DEntry> rawTo50 = takeoffEntries.map((e) => Performance3DEntry(
      altitude: e.altitude, temp: e.temp, weight: e.weight, value: e.over50ft,
    )).toList();
    
    List<Performance3DEntry> rawLdRoll = landingEntries.map((e) => Performance3DEntry(
      altitude: e.altitude, temp: e.temp, weight: e.weight, value: e.groundRoll,
    )).toList();
    
    List<Performance3DEntry> rawLd50 = landingEntries.map((e) => Performance3DEntry(
      altitude: e.altitude, temp: e.temp, weight: e.weight, value: e.over50ft,
    )).toList();
    
    List<Cruise3DEntry> rawCruise = cruiseEntries.map((e) => Cruise3DEntry(
      altitude: e.altitude.toDouble(), temp: e.temp.toDouble(),
      powerPercent: e.powerPercent.toDouble(), ktas: e.ktas, gph: e.gph,
    )).toList();
    
    return AircraftPerformanceData(
      name: aircraft.tail.isNotEmpty ? aircraft.tail : 'Custom',
      icaoType: aircraft.type,
      maxGrossWeight: aircraft.maxGrossWeight > 0 ? aircraft.maxGrossWeight : 2400,
      usableFuel: aircraft.usableFuel > 0 ? aircraft.usableFuel : 48,
      emptyWeight: aircraft.emptyWeight > 0 ? aircraft.emptyWeight : 1500,
      takeoffGroundRoll: _buildDummyTable(),
      takeoffOver50ft: _buildDummyTable(),
      landingGroundRoll: _buildDummyTable(),
      landingOver50ft: _buildDummyTable(),
      cruiseTable: CruisePerformanceTable(entries: []),
      rawTakeoffRollEntries: rawToRoll,
      rawTakeoff50ftEntries: rawTo50,
      rawLandingRollEntries: rawLdRoll,
      rawLanding50ftEntries: rawLd50,
      rawCruiseEntries: rawCruise,
      takeoffHeadwindPct: toHeadwindPct,
      takeoffTailwindPct: toTailwindPct,
      takeoffSoftFieldPct: toSoftFieldPct,
      landingHeadwindPct: ldHeadwindPct,
      landingTailwindPct: ldTailwindPct,
      landingSoftFieldPct: ldSoftFieldPct,
    );
  }
  
  Aircraft _performanceDataToAircraft(AircraftPerformanceData perfData, [Map<String, dynamic>? legacyMap]) {
    List<Map<String, dynamic>> takeoffEntries = [];
    List<Map<String, dynamic>> landingEntries = [];
    List<Map<String, dynamic>> cruiseEntries = [];
    
    if (legacyMap != null) {
      takeoffEntries = (legacyMap['takeoffEntries'] as List?)?.map((e) => e as Map<String, dynamic>).toList() ?? [];
      landingEntries = (legacyMap['landingEntries'] as List?)?.map((e) => e as Map<String, dynamic>).toList() ?? [];
      cruiseEntries = (legacyMap['cruiseEntries'] as List?)?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    }
    
    return Aircraft(
      tail: perfData.name,
      type: perfData.icaoType,
      wake: 'LIGHT',
      icao: '',
      equipment: 'S',
      cruiseTas: '',
      surveillance: 'N',
      fuelEndurance: '',
      color: '',
      pic: '',
      picInfo: '',
      sinkRate: '',
      fuelBurn: '',
      base: '',
      other: '',
      maxGrossWeight: perfData.maxGrossWeight,
      usableFuel: perfData.usableFuel,
      emptyWeight: perfData.emptyWeight,
      takeoffData: jsonEncode({
        'entries': takeoffEntries,
        'headwindPct': perfData.takeoffHeadwindPct,
        'tailwindPct': perfData.takeoffTailwindPct,
        'softFieldPct': perfData.takeoffSoftFieldPct,
      }),
      landingData: jsonEncode({
        'entries': landingEntries,
        'headwindPct': perfData.landingHeadwindPct,
        'tailwindPct': perfData.landingTailwindPct,
        'softFieldPct': perfData.landingSoftFieldPct,
      }),
      cruiseData: jsonEncode(cruiseEntries),
    );
  }
  
  Future<void> _loadSelectedAircraft() async {
    List<Map<String, dynamic>> settings = await UserDatabaseHelper.db.getAllSettings();
    for (var s in settings) {
      if (s['key'] == 'lastPerformanceAircraft') {
        String name = s['value'] ?? '';
        AircraftPerformanceData? match = _allAircraft.cast<AircraftPerformanceData?>().firstWhere(
          (a) => a!.name == name,
          orElse: () => null,
        );
        if (match != null) {
          _selectedAircraft = match;
        }
        break;
      }
    }
  }
  
  Future<void> _saveSelectedAircraft() async {
    await UserDatabaseHelper.db.insertSetting('lastPerformanceAircraft', _selectedAircraft.name);
  }

  void _ensureSelectedAircraftInList() {
    List<AircraftPerformanceData> all = _allAircraft;
    if (!all.contains(_selectedAircraft)) {
      AircraftPerformanceData? match = all.cast<AircraftPerformanceData?>().firstWhere(
        (a) => a!.name == _selectedAircraft.name,
        orElse: () => null,
      );
      _selectedAircraft = match ?? CommonAircraftData.cessna172sp;
    }
  }

  AircraftPerformanceData _customAircraftFromMap(Map<String, dynamic> map) {
    List<_TakeoffLandingEntry> takeoffEntries = (map['takeoffEntries'] as List?)
        ?.map((e) => _TakeoffLandingEntry.fromMap(e))
        .toList() ?? [];
    List<_TakeoffLandingEntry> landingEntries = (map['landingEntries'] as List?)
        ?.map((e) => _TakeoffLandingEntry.fromMap(e))
        .toList() ?? [];
    List<_CruiseEntry> cruiseEntries = (map['cruiseEntries'] as List?)
        ?.map((e) => _CruiseEntry.fromMap(e))
        .toList() ?? [];

    List<Performance3DEntry> rawToRoll = takeoffEntries.map((e) => Performance3DEntry(
      altitude: e.altitude,
      temp: e.temp,
      weight: e.weight,
      value: e.groundRoll,
    )).toList();
    
    List<Performance3DEntry> rawTo50 = takeoffEntries.map((e) => Performance3DEntry(
      altitude: e.altitude,
      temp: e.temp,
      weight: e.weight,
      value: e.over50ft,
    )).toList();
    
    List<Performance3DEntry> rawLdRoll = landingEntries.map((e) => Performance3DEntry(
      altitude: e.altitude,
      temp: e.temp,
      weight: e.weight,
      value: e.groundRoll,
    )).toList();
    
    List<Performance3DEntry> rawLd50 = landingEntries.map((e) => Performance3DEntry(
      altitude: e.altitude,
      temp: e.temp,
      weight: e.weight,
      value: e.over50ft,
    )).toList();
    
    List<Cruise3DEntry> rawCruise = cruiseEntries.map((e) => Cruise3DEntry(
      altitude: e.altitude.toDouble(),
      temp: e.temp.toDouble(),
      powerPercent: e.powerPercent.toDouble(),
      ktas: e.ktas,
      gph: e.gph,
    )).toList();

    return AircraftPerformanceData(
      name: map['name'] ?? 'Custom',
      icaoType: map['icaoType'] ?? '',
      maxGrossWeight: (map['maxGrossWeight'] ?? 2400).toDouble(),
      usableFuel: (map['usableFuel'] ?? 48).toDouble(),
      emptyWeight: (map['emptyWeight'] ?? 1500).toDouble(),
      takeoffGroundRoll: _buildDummyTable(),
      takeoffOver50ft: _buildDummyTable(),
      landingGroundRoll: _buildDummyTable(),
      landingOver50ft: _buildDummyTable(),
      cruiseTable: CruisePerformanceTable(entries: []),
      rawTakeoffRollEntries: rawToRoll,
      rawTakeoff50ftEntries: rawTo50,
      rawLandingRollEntries: rawLdRoll,
      rawLanding50ftEntries: rawLd50,
      rawCruiseEntries: rawCruise,
      takeoffHeadwindPct: (map['takeoffHeadwindPct'] ?? map['headwindPercentPerKt'] ?? 1.5).toDouble(),
      takeoffTailwindPct: (map['takeoffTailwindPct'] ?? map['tailwindPercentPerKt'] ?? 10.0).toDouble(),
      takeoffSoftFieldPct: (map['takeoffSoftFieldPct'] ?? map['softFieldTakeoffPercent'] ?? 15.0).toDouble(),
      landingHeadwindPct: (map['landingHeadwindPct'] ?? map['headwindPercentPerKt'] ?? 1.5).toDouble(),
      landingTailwindPct: (map['landingTailwindPct'] ?? map['tailwindPercentPerKt'] ?? 10.0).toDouble(),
      landingSoftFieldPct: (map['landingSoftFieldPct'] ?? map['softFieldLandingPercent'] ?? 20.0).toDouble(),
    );
  }
  
  PerformanceTable _buildDummyTable() {
    return PerformanceTable(
      pressureAltitudes: [0],
      temperatures: [15],
      values: [[1000]],
    );
  }

  Future<String?> _getCustomAircraftData() async {
    List<Map<String, dynamic>> settings = await UserDatabaseHelper.db.getAllSettings();
    for (var s in settings) {
      if (s['key'] == 'customAircraftPerformance') {
        return s['value'];
      }
    }
    return null;
  }

  Future<void> _saveCustomAircraftToDb(Aircraft aircraft) async {
    await UserDatabaseHelper.db.addAircraft(aircraft);
  }
  
  Future<void> _deleteCustomAircraftFromDb(String name) async {
    await UserDatabaseHelper.db.deleteAircraft(name);
  }

  @override
  void dispose() {
    _takeoffPressureAltController.dispose();
    _takeoffTempController.dispose();
    _takeoffWeightController.dispose();
    _takeoffHeadwindController.dispose();
    _landingPressureAltController.dispose();
    _landingTempController.dispose();
    _landingWeightController.dispose();
    _landingHeadwindController.dispose();
    _cruiseAltitudeController.dispose();
    _cruiseTempController.dispose();
    _fuelDistanceController.dispose();
    _fuelGroundSpeedController.dispose();
    _fuelFlowController.dispose();
    _fuelReserveController.dispose();
    _fuelTaxiController.dispose();
    _customNameController.dispose();
    _customIcaoController.dispose();
    _customMaxWeightController.dispose();
    _customUsableFuelController.dispose();
    _customToHeadwindController.dispose();
    _customToTailwindController.dispose();
    _customToSoftFieldController.dispose();
    _customLdHeadwindController.dispose();
    _customLdTailwindController.dispose();
    _customLdSoftFieldController.dispose();
    _customEmptyWeightController.dispose();
    _customColorController.dispose();
    _customModeSController.dispose();
    _customPicController.dispose();
    _customPicInfoController.dispose();
    _customBaseController.dispose();
    _customEquipmentController.dispose();
    _customSurveillanceController.dispose();
    _customOtherController.dispose();
    _customCruiseTasController.dispose();
    _customFuelEnduranceController.dispose();
    _customSinkRateController.dispose();
    super.dispose();
  }

  List<AircraftPerformanceData> get _allAircraft => [...CommonAircraftData.all, ..._customAircraft];

  @override
  Widget build(BuildContext context) {
    List<Widget> pages = [
      _buildTakeoffTab(),
      _buildLandingTab(),
      _buildCruiseTab(),
      _buildFuelTab(),
      _buildWnbTab(),
      _buildCustomTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text('Performance'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton2<AircraftPerformanceData>(
                buttonStyleData: ButtonStyleData(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                ),
                dropdownStyleData: DropdownStyleData(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                  maxHeight: 400,
                ),
                isExpanded: false,
                value: _selectedAircraft,
                items: _allAircraft.map((a) => DropdownMenuItem<AircraftPerformanceData>(
                  value: a,
                  child: Text(a.name, style: TextStyle(fontSize: Constants.dropDownButtonFontSize)),
                )).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedAircraft = value;
                      _takeoffWeightController.text = value.maxGrossWeight.toStringAsFixed(0);
                      _landingWeightController.text = (value.maxGrossWeight * 0.9).toStringAsFixed(0);
                      CruiseResult cruise = value.getCruisePerformance(8000, 65);
                      _fuelFlowController.text = cruise.gph.toStringAsFixed(1);
                    });
                    _saveSelectedAircraft();
                    _loadWnbForAircraft();
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: pages[_pageIndex]),
          Padding(
            padding: const EdgeInsets.all(5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < _pageLabels.length; i++)
                    TextButton(
                      style: _pageIndex == i
                          ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                          : null,
                      onPressed: () => setState(() => _pageIndex = i),
                      child: Text(_pageLabels[i]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTakeoffTab() {
    double pressureAlt = double.tryParse(_takeoffPressureAltController.text) ?? 0;
    double temp = double.tryParse(_takeoffTempController.text) ?? 15;
    double weight = double.tryParse(_takeoffWeightController.text) ?? _selectedAircraft.maxGrossWeight;
    double headwind = double.tryParse(_takeoffHeadwindController.text) ?? 0;

    double densityAlt = PerformanceCalculator.calculateDensityAltitude(pressureAlt, temp);

    double groundRoll = _selectedAircraft.getTakeoffGroundRoll(
      pressureAlt, temp, weight, headwind, _takeoffSoftField,
    );
    double distance50 = _selectedAircraft.getTakeoffOver50ft(
      pressureAlt, temp, weight, headwind, _takeoffSoftField,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResultCard(
            'Takeoff Performance (POH Interpolated)',
            Icons.flight_takeoff,
            [
              _ResultRow('Ground Roll', '${groundRoll.round()} ft'),
              _ResultRow('Over 50ft Obstacle', '${distance50.round()} ft'),
              _ResultRow('Density Altitude', '${densityAlt.round()} ft'),
            ],
            groundRoll > 3000 ? Colors.red : (groundRoll > 2000 ? Colors.orange : Colors.green),
          ),
          const SizedBox(height: 16),
          _buildInputCard(
            'Input Parameters',
            Icons.tune,
            [
              _buildTextField('Pressure Altitude (ft)', _takeoffPressureAltController, keyboard: TextInputType.number),
              _buildTextField('Temperature (°C)', _takeoffTempController, keyboard: const TextInputType.numberWithOptions(signed: true, decimal: true)),
              _buildTextField('Takeoff Weight (lbs)', _takeoffWeightController, keyboard: TextInputType.number),
              _buildTextField('Headwind (kts, negative=tailwind)', _takeoffHeadwindController, keyboard: const TextInputType.numberWithOptions(signed: true)),
              _buildSwitch('Soft/Grass Field', _takeoffSoftField, (v) => setState(() => _takeoffSoftField = v)),
            ],
          ),
          const SizedBox(height: 16),
          _buildPohNoteCard(),
        ],
      ),
    );
  }

  Widget _buildLandingTab() {
    double pressureAlt = double.tryParse(_landingPressureAltController.text) ?? 0;
    double temp = double.tryParse(_landingTempController.text) ?? 15;
    double weight = double.tryParse(_landingWeightController.text) ?? _selectedAircraft.maxGrossWeight * 0.9;
    double headwind = double.tryParse(_landingHeadwindController.text) ?? 0;

    double densityAlt = PerformanceCalculator.calculateDensityAltitude(pressureAlt, temp);

    double groundRoll = _selectedAircraft.getLandingGroundRoll(
      pressureAlt, temp, weight, headwind, _landingSoftField,
    );
    double distance50 = _selectedAircraft.getLandingOver50ft(
      pressureAlt, temp, weight, headwind, _landingSoftField,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResultCard(
            'Landing Performance (POH Interpolated)',
            Icons.flight_land,
            [
              _ResultRow('Ground Roll', '${groundRoll.round()} ft'),
              _ResultRow('Over 50ft Obstacle', '${distance50.round()} ft'),
              _ResultRow('Density Altitude', '${densityAlt.round()} ft'),
            ],
            groundRoll > 2500 ? Colors.red : (groundRoll > 1500 ? Colors.orange : Colors.green),
          ),
          const SizedBox(height: 16),
          _buildInputCard(
            'Input Parameters',
            Icons.tune,
            [
              _buildTextField('Pressure Altitude (ft)', _landingPressureAltController, keyboard: TextInputType.number),
              _buildTextField('Temperature (°C)', _landingTempController, keyboard: const TextInputType.numberWithOptions(signed: true, decimal: true)),
              _buildTextField('Landing Weight (lbs)', _landingWeightController, keyboard: TextInputType.number),
              _buildTextField('Headwind (kts, negative=tailwind)', _landingHeadwindController, keyboard: const TextInputType.numberWithOptions(signed: true)),
              _buildSwitch('Soft/Grass Field', _landingSoftField, (v) => setState(() => _landingSoftField = v)),
            ],
          ),
          const SizedBox(height: 16),
          _buildPohNoteCard(),
        ],
      ),
    );
  }

  Widget _buildCruiseTab() {
    int altitude = int.tryParse(_cruiseAltitudeController.text) ?? 8000;
    int temp = int.tryParse(_cruiseTempController.text) ?? 0;

    CruiseResult performance = _selectedAircraft.getCruisePerformance(altitude, _cruisePowerPercent, temp);

    double usableFuel = _selectedAircraft.usableFuel;
    double enduranceHours = performance.gph > 0 ? usableFuel / performance.gph : 0;
    double range = performance.ktas * enduranceHours * 0.9;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResultCard(
            'Cruise Performance (POH Interpolated)',
            MdiIcons.airplane,
            [
              _ResultRow('True Airspeed', '${performance.ktas.round()} kts'),
              _ResultRow('Fuel Flow', '${performance.gph.toStringAsFixed(1)} gph'),
              _ResultRow('Endurance (no reserve)', '${enduranceHours.toStringAsFixed(1)} hrs'),
              _ResultRow('Range (w/ 45min reserve)', '${range.round()} nm'),
            ],
            Colors.blue,
          ),
          const SizedBox(height: 16),
          _buildCruiseTableCard(),
          const SizedBox(height: 16),
          _buildInputCard(
            'Input Parameters',
            Icons.tune,
            [
              _buildTextField('Cruise Altitude (ft)', _cruiseAltitudeController, keyboard: TextInputType.number),
              _buildTextField('Temperature deviation from std (°C)', _cruiseTempController, keyboard: const TextInputType.numberWithOptions(signed: true)),
              _buildPowerSlider(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFuelTab() {
    double distance = double.tryParse(_fuelDistanceController.text) ?? 200;
    double groundSpeed = double.tryParse(_fuelGroundSpeedController.text) ?? 110;
    double fuelFlow = double.tryParse(_fuelFlowController.text) ?? 8.5;
    double reserve = double.tryParse(_fuelReserveController.text) ?? 45;
    double taxi = double.tryParse(_fuelTaxiController.text) ?? 1.0;

    FuelCalculation calc = FuelCalculation.calculate(
      distance: distance,
      groundSpeed: groundSpeed,
      fuelFlowGph: fuelFlow,
      reserveMinutes: reserve,
      taxiFuel: taxi,
    );

    bool fuelOk = calc.totalFuel <= _selectedAircraft.usableFuel;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResultCard(
            'Fuel Requirements',
            MdiIcons.fuel,
            [
              _ResultRow('Flight Time', '${calc.flightTime.inHours}h ${calc.flightTime.inMinutes % 60}m'),
              _ResultRow('Trip Fuel', '${calc.tripFuel.toStringAsFixed(1)} gal'),
              _ResultRow('Reserve Fuel', '${calc.reserveFuel.toStringAsFixed(1)} gal'),
              _ResultRow('Taxi Fuel', '${calc.taxiFuel.toStringAsFixed(1)} gal'),
              _ResultRow('Total Required', '${calc.totalFuel.toStringAsFixed(1)} gal', bold: true),
              _ResultRow('Usable Fuel', '${_selectedAircraft.usableFuel.toStringAsFixed(1)} gal'),
            ],
            fuelOk ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 16),
          if (!fuelOk)
            Card(
              color: Colors.red.withAlpha(30),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Insufficient fuel! Need ${(calc.totalFuel - _selectedAircraft.usableFuel).toStringAsFixed(1)} gal more than usable capacity.',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          _buildInputCard(
            'Input Parameters',
            Icons.tune,
            [
              _buildTextField('Distance (nm)', _fuelDistanceController, keyboard: TextInputType.number),
              _buildTextField('Ground Speed (kts)', _fuelGroundSpeedController, keyboard: TextInputType.number),
              _buildTextField('Fuel Flow (gph)', _fuelFlowController, keyboard: const TextInputType.numberWithOptions(decimal: true)),
              _buildTextField('Reserve (minutes)', _fuelReserveController, keyboard: TextInputType.number),
              _buildTextField('Taxi Fuel (gal)', _fuelTaxiController, keyboard: const TextInputType.numberWithOptions(decimal: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWnbTab() {
    Offset cg = _calculateCG();
    bool isInside = _isCGWithinLimits();
    
    FlDotPainter getDotPainter(double size, Color color) {
      return FlDotCirclePainter(color: color, radius: size);
    }
    
    List<ScatterSpot> makeSpotData() {
      List<ScatterSpot> spots = _wnbEnvelopePoints.asMap().entries.map((e) {
        return ScatterSpot(e.value.dx, e.value.dy, dotPainter: getDotPainter(4, Colors.blueAccent));
      }).toList();
      spots.insert(0, ScatterSpot(cg.dx, cg.dy, dotPainter: getDotPainter(8, isInside ? Colors.green : Colors.red)));
      return spots;
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Card
          Card(
            color: isInside ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isInside ? Icons.check_circle : Icons.warning,
                    color: isInside ? Colors.green : Colors.red,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isInside ? "Within Limits" : "Outside Limits",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isInside ? Colors.green : Colors.red,
                          ),
                        ),
                        Text(
                          "CG: ${cg.dx.toStringAsFixed(2)} in | Weight: ${cg.dy.toStringAsFixed(1)} lbs",
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // CG Envelope Chart
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.show_chart, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        "CG Envelope",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      if (_wnbEditing)
                        Text("Tap to add/remove points", style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Envelope limits
                  if (_wnbEditing)
                    Row(
                      children: [
                        Expanded(child: _buildWnbLimitField("Arm Min", _wnbMinArm, (v) => setState(() => _wnbMinArm = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildWnbLimitField("Arm Max", _wnbMaxArm, (v) => setState(() => _wnbMaxArm = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildWnbLimitField("Wt Min", _wnbMinWeight, (v) => setState(() => _wnbMinWeight = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildWnbLimitField("Wt Max", _wnbMaxWeight, (v) => setState(() => _wnbMaxWeight = v))),
                      ],
                    ),
                  if (_wnbEditing) const SizedBox(height: 16),
                  
                  // Chart
                  AspectRatio(
                    aspectRatio: 1.2,
                    child: LayoutBuilder(builder: (context, constraints) {
                      Offset pixelToCoordinate(Offset offset, BoxConstraints constraints) {
                        double reservedSize = 44 + 16;
                        return Offset(
                          _wnbMinArm + (_wnbMaxArm - _wnbMinArm) * (offset.dx) / (constraints.maxWidth - reservedSize),
                          (_wnbMaxWeight + _wnbMinWeight) - (_wnbMinWeight + (_wnbMaxWeight - _wnbMinWeight) * (offset.dy) / (constraints.maxHeight - reservedSize)));
                      }

                      return ScatterChart(
                        ScatterChartData(
                          titlesData: const FlTitlesData(
                            leftTitles: AxisTitles(axisNameSize: 16, axisNameWidget: Text("Weight (lbs)"), sideTitles: SideTitles(reservedSize: 44, showTitles: true)),
                            bottomTitles: AxisTitles(axisNameSize: 16, axisNameWidget: Text("Arm (in)"),  sideTitles: SideTitles(reservedSize: 44, showTitles: true)),
                            rightTitles: AxisTitles(sideTitles: SideTitles(reservedSize: 0, showTitles: false)),
                            topTitles: AxisTitles(sideTitles: SideTitles(reservedSize: 0, showTitles: false)),
                            show: true,
                          ),
                          scatterSpots: makeSpotData(),
                          minX: _wnbMinArm,
                          minY: _wnbMinWeight,
                          maxX: _wnbMaxArm,
                          maxY: _wnbMaxWeight,
                          gridData: FlGridData(
                            show: true,
                            drawHorizontalLine: true,
                            checkToShowHorizontalLine: (value) => true,
                            getDrawingHorizontalLine: (value) => FlLine(color: Theme.of(context).colorScheme.outlineVariant),
                            drawVerticalLine: true,
                            checkToShowVerticalLine: (value) => true,
                            getDrawingVerticalLine: (value) => FlLine(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          scatterTouchData: ScatterTouchData(
                            touchSpotThreshold: 10,
                            enabled: true,
                            handleBuiltInTouches: false,
                            touchCallback: (FlTouchEvent event, ScatterTouchResponse? touchResponse) {
                              if (event is FlTapUpEvent && _wnbEditing) {
                                if (touchResponse != null) {
                                  ScatterTouchedSpot? spot = touchResponse.touchedSpot;
                                  if (spot != null) {
                                    setState(() {
                                      if (spot.spotIndex > 0) {
                                        _wnbEnvelopePoints.removeAt(spot.spotIndex - 1);
                                      }
                                    });
                                  } else {
                                    setState(() {
                                      _wnbEnvelopePoints.add(pixelToCoordinate(event.details.localPosition, constraints));
                                    });
                                  }
                                }
                              }
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Weight Items Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.scale, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        "Weight Stations",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      if (_wnbEditing)
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            setState(() {
                              _wnbStations.add(_WnbStation(name: 'New Station', arm: 40, weight: 0));
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildWnbStationsTable(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Info about aircraft type (only for predefined aircraft)
          if (!_isCustomAircraft())
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Predefined aircraft - W&B data from POH (read-only)",
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!_isCustomAircraft()) const SizedBox(height: 16),
          
          // Action Buttons (only for custom aircraft)
          if (_isCustomAircraft())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_wnbEditing)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text("Reset"),
                      onPressed: () {
                        _loadWnbForAircraft();
                        setState(() => _wnbEditing = false);
                      },
                    ),
                  if (_wnbEditing) const SizedBox(width: 16),
                  ElevatedButton.icon(
                    icon: Icon(_wnbEditing ? Icons.save : Icons.edit),
                    label: Text(_wnbEditing ? "Save" : "Edit"),
                    onPressed: () async {
                      if (_wnbEditing) {
                        await _saveWnbData();
                      }
                      setState(() => _wnbEditing = !_wnbEditing);
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
  
  Widget _buildWnbLimitField(String label, double value, Function(double) onChanged) {
    return TextFormField(
      initialValue: value.toString(),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
      onChanged: (v) {
        try {
          onChanged(double.parse(v));
        } catch (e) {
          // ignore
        }
      },
    );
  }
  
  Widget _buildWnbStationsTable() {
    double totalMoment = 0;
    
    List<Widget> rows = [];
    
    // Header row
    rows.add(
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text("Station", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
            Expanded(flex: 2, child: Text("Weight", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text("Arm", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text("Moment", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
            if (_wnbEditing) const SizedBox(width: 40),
          ],
        ),
      ),
    );
    
    for (int i = 0; i < _wnbStations.length; i++) {
      var station = _wnbStations[i];
      totalMoment += station.moment;
      
      rows.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextFormField(
                    enabled: _wnbEditing,
                    initialValue: station.name,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) => station.name = value,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextFormField(
                    initialValue: station.weight.toStringAsFixed(1),
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      try {
                        setState(() => station.weight = double.parse(value));
                      } catch (e) {
                        // ignore
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextFormField(
                    enabled: _wnbEditing,
                    initialValue: station.arm.toStringAsFixed(1),
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      try {
                        setState(() => station.arm = double.parse(value));
                      } catch (e) {
                        // ignore
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      station.moment.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              if (_wnbEditing)
                SizedBox(
                  width: 40,
                  child: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: () => setState(() => _wnbStations.removeAt(i)),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    
    Offset cg = _calculateCG();
    bool isInside = _isCGWithinLimits();
    
    // Total row
    rows.add(
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isInside ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isInside ? Colors.green : Colors.red),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text(cg.dy.toStringAsFixed(1), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text(cg.dx.toStringAsFixed(2), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text(totalMoment.toStringAsFixed(0), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
            if (_wnbEditing) const SizedBox(width: 40),
          ],
        ),
      ),
    );
    
    return Column(children: rows);
  }
  
  Future<void> _saveWnbData() async {
    // Convert current W&B data to JSON
    List<WnbStationDef> stationDefs = _wnbStations.map((s) => WnbStationDef(name: s.name, arm: s.arm, defaultWeight: s.weight)).toList();
    WnbData wnbData = WnbData(
      stations: stationDefs,
      envelopePoints: _wnbEnvelopePoints,
      minArm: _wnbMinArm,
      maxArm: _wnbMaxArm,
      minWeight: _wnbMinWeight,
      maxWeight: _wnbMaxWeight,
    );
    
    // Get existing aircraft from database or create new
    try {
      Aircraft aircraft = await UserDatabaseHelper.db.getAircraft(_selectedAircraft.name);
      aircraft = aircraft.copyWith(wnbData: wnbData.toJson());
      await UserDatabaseHelper.db.addAircraft(aircraft);
    } catch (e) {
      // Aircraft not in database, create minimal entry with W&B data
      Aircraft aircraft = Aircraft(
        tail: _selectedAircraft.name,
        type: _selectedAircraft.icaoType,
        wake: 'LIGHT',
        icao: '',
        equipment: 'S',
        cruiseTas: '',
        surveillance: 'N',
        fuelEndurance: '',
        color: '',
        pic: '',
        picInfo: '',
        sinkRate: '',
        fuelBurn: '',
        base: '',
        other: '',
        maxGrossWeight: _selectedAircraft.maxGrossWeight,
        usableFuel: _selectedAircraft.usableFuel,
        emptyWeight: _selectedAircraft.emptyWeight,
        wnbData: wnbData.toJson(),
      );
      await UserDatabaseHelper.db.addAircraft(aircraft);
    }
  }

  Widget _buildCustomTab() {
    if (_showCustomEntry) {
      return _buildCustomEntryForm();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.airplanemode_active, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Custom Aircraft Profiles',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_customAircraft.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No custom aircraft profiles.\nEnter POH data to add one.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ...(_customAircraft.map((a) => _buildCustomAircraftTile(a))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              _populateFromSelectedAircraft();
              setState(() => _showCustomEntry = true);
            },
            icon: const Icon(Icons.add),
            label: Text('Customize ${_selectedAircraft.name.split(' ').first}'),
          ),
          const SizedBox(height: 32),
          _buildAircraftSpecsCard(),
        ],
      ),
    );
  }

  Widget _buildCustomEntryForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Aircraft Identification Section
          _buildSectionCard(
            'Aircraft Identification',
            Icons.airplanemode_active,
            [
              _buildTextField('Tail Number', _customNameController, tooltip: 'Tail number, e.g. N172EF'),
              _buildTextField('Type', _customIcaoController, tooltip: 'Aircraft type code, e.g. C172'),
              _buildIconDropdown(),
              _buildTextField('Color & Markings', _customColorController, tooltip: 'Color codes: W=White, B=Blue, R=Red, etc.'),
              _buildTextField('Mode S Code', _customModeSController, tooltip: 'Mode S code in hex (registry.faa.gov)'),
            ],
          ),
          const SizedBox(height: 12),
          
          // Pilot Information Section
          _buildSectionCard(
            'Pilot Information',
            Icons.person,
            [
              _buildTextField('PIC', _customPicController, tooltip: 'Pilot in Command name'),
              _buildTextField('PIC Information', _customPicInfoController, tooltip: 'Pilot info, e.g. phone number'),
              _buildTextField('Home Base', _customBaseController, tooltip: 'Home base airport, e.g. KBVY'),
            ],
          ),
          const SizedBox(height: 12),
          
          // Performance Settings Section
          _buildSectionCard(
            'Performance Settings',
            Icons.speed,
            [
              _buildTextField('Max Gross Weight (lbs)', _customMaxWeightController, keyboard: TextInputType.number),
              _buildTextField('Empty Weight (lbs)', _customEmptyWeightController, keyboard: TextInputType.number),
              _buildTextField('Usable Fuel (gal)', _customUsableFuelController, keyboard: const TextInputType.numberWithOptions(decimal: true)),
              _buildTextField('Cruise Speed (ktas)', _customCruiseTasController, keyboard: TextInputType.number, tooltip: 'Cruise true airspeed in knots'),
              _buildTextField('Fuel Endurance (hrs)', _customFuelEnduranceController, keyboard: const TextInputType.numberWithOptions(decimal: true)),
              _buildTextField('Sink Rate (fpm)', _customSinkRateController, keyboard: TextInputType.number),
              _buildWakeDropdown(),
            ],
          ),
          const SizedBox(height: 12),
          
          // Equipment Section
          _buildSectionCard(
            'Equipment',
            Icons.settings_input_antenna,
            [
              _buildTextField('Equipment', _customEquipmentController, tooltip: 'D=DME, G=GNSS, I=INS, L=ILS, O=VOR, S=Standard'),
              _buildTextField('Surveillance', _customSurveillanceController, tooltip: 'N=None, A=Mode A, C=Modes A+C, S=Mode S'),
              _buildTextField('Other Information', _customOtherController, tooltip: 'STS/, PBN/, NAV/, etc.'),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildCombinedTableCard(
            'TAKEOFF PERFORMANCE',
            'Enter ground roll and 50ft obstacle distances from POH',
            _customTakeoffEntries,
            () => setState(() {
                try {
                  _customTakeoffEntries.add(_customTakeoffEntries[_customTakeoffEntries.length - 1]);
                }
                catch (e) {
                  _customTakeoffEntries.add(_TakeoffLandingEntry(altitude: 0, temp: 15, weight: 2400, groundRoll: 900, over50ft: 1500));
                }
              }
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Takeoff Corrections', style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, 
                    color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Headwind (%/kt)', _customToHeadwindController, 
                        keyboard: const TextInputType.numberWithOptions(decimal: true))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTextField('Tailwind (%/kt)', _customToTailwindController, 
                        keyboard: const TextInputType.numberWithOptions(decimal: true))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTextField('Soft Field (%)', _customToSoftFieldController, 
                        keyboard: TextInputType.number)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          _buildCombinedTableCard(
            'LANDING PERFORMANCE',
            'Enter ground roll and 50ft obstacle distances from POH',
            _customLandingEntries,
            () => setState(() {
                try {
                  _customLandingEntries.add(_customLandingEntries[_customLandingEntries.length - 1]);
                }
                catch (e) {
                  _customLandingEntries.add(_TakeoffLandingEntry(altitude: 0, temp: 15, weight: 2400, groundRoll: 550, over50ft: 1300));
                }
              }
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Landing Corrections', style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, 
                    color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Headwind (%/kt)', _customLdHeadwindController, 
                        keyboard: const TextInputType.numberWithOptions(decimal: true))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTextField('Tailwind (%/kt)', _customLdTailwindController, 
                        keyboard: const TextInputType.numberWithOptions(decimal: true))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTextField('Soft Field (%)', _customLdSoftFieldController, 
                        keyboard: TextInputType.number)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          _buildCruiseTableCard2(),
          const SizedBox(height: 24),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _showCustomEntry = false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saveCustomAircraftEntry,
                child: const Text('Save Aircraft'),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCombinedTableCard(String title, String subtitle, List<_TakeoffLandingEntry> entries, VoidCallback onAdd) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green),
                  tooltip: 'Add entry',
                  onPressed: onAdd,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: const [
                  Expanded(flex: 2, child: Text('Alt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('Temp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('Wt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('Roll', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('50ft', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  SizedBox(width: 36),
                ],
              ),
            ),
            ...entries.asMap().entries.map((e) => _buildCombinedEntryRow(e.key, e.value, entries)),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedEntryRow(int index, _TakeoffLandingEntry entry, List<_TakeoffLandingEntry> list) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.altitude.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.altitude = double.tryParse(v) ?? 0,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.temp.toStringAsFixed(0),
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.temp = double.tryParse(v) ?? 15,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.weight.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.weight = double.tryParse(v) ?? 2400,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.groundRoll.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.groundRoll = double.tryParse(v) ?? 0,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.over50ft.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.over50ft = double.tryParse(v) ?? 0,
            ),
          ),
          SizedBox(
            width: 36,
            child: IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 18),
              padding: EdgeInsets.zero,
              onPressed: list.length > 1 ? () => setState(() => list.removeAt(index)) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCruiseTableCard2() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CRUISE PERFORMANCE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('Enter values at different altitudes, temps, and power settings', 
                           style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green),
                  tooltip: 'Add cruise entry',
                  onPressed: () => setState(() {
                    try {
                      _customCruiseEntries.add(_customCruiseEntries[_customCruiseEntries.length - 1]);
                    }
                    catch (e) {
                      _customCruiseEntries.add(_CruiseEntry());
                    }
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: const [
                  Expanded(flex: 2, child: Text('Alt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('Temp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('Pwr%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('KTAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('GPH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center)),
                  SizedBox(width: 40),
                ],
              ),
            ),
            ..._customCruiseEntries.asMap().entries.map((e) => _buildCruiseEntryRow(e.key, e.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildCruiseEntryRow(int index, _CruiseEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.altitude.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.altitude = int.tryParse(v) ?? 8000,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.temp.toString(),
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.temp = int.tryParse(v) ?? 0,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.powerPercent.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.powerPercent = int.tryParse(v) ?? 65,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.ktas.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.ktas = double.tryParse(v) ?? 110,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: entry.gph.toStringAsFixed(1),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => entry.gph = double.tryParse(v) ?? 8.5,
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
              padding: EdgeInsets.zero,
              onPressed: _customCruiseEntries.length > 1 
                  ? () => setState(() => _customCruiseEntries.removeAt(index)) 
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomAircraftTile(AircraftPerformanceData aircraft) {
    return ListTile(
      leading: Icon(MdiIcons.airplane),
      title: Text(aircraft.name),
      subtitle: Text(aircraft.icaoType),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () {
          bool wasSelected = _selectedAircraft.name == aircraft.name;
          setState(() {
            _customAircraft.removeWhere((a) => a.name == aircraft.name);
            if (wasSelected) {
              _selectedAircraft = CommonAircraftData.cessna172sp;
              _saveSelectedAircraft();
            }
          });
          _deleteCustomAircraftFromDb(aircraft.name);
          if (wasSelected) {
            _loadWnbForAircraft();
          }
        },
      ),
      onTap: () {
        setState(() {
          _selectedAircraft = aircraft;
          _pageIndex = 0;
        });
        _saveSelectedAircraft();
        _loadWnbForAircraft();
      },
    );
  }

  void _saveCustomAircraftEntry() {
    String tailNumber = _customNameController.text.trim().toUpperCase();
    if (tailNumber.isEmpty) {
      tailNumber = 'CUSTOM';
    }
    
    // Ensure unique tail number
    String baseName = tailNumber;
    int suffix = 1;
    while (_allAircraft.any((a) => a.name == tailNumber)) {
      suffix++;
      tailNumber = '$baseName$suffix';
    }

    double maxWeight = double.tryParse(_customMaxWeightController.text) ?? 2400;
    double usableFuel = double.tryParse(_customUsableFuelController.text) ?? 48;
    double emptyWeight = double.tryParse(_customEmptyWeightController.text) ?? maxWeight * 0.6;

    double toHeadwindPct = double.tryParse(_customToHeadwindController.text) ?? 1.5;
    double toTailwindPct = double.tryParse(_customToTailwindController.text) ?? 10.0;
    double toSoftFieldPct = double.tryParse(_customToSoftFieldController.text) ?? 15.0;
    double ldHeadwindPct = double.tryParse(_customLdHeadwindController.text) ?? 1.5;
    double ldTailwindPct = double.tryParse(_customLdTailwindController.text) ?? 10.0;
    double ldSoftFieldPct = double.tryParse(_customLdSoftFieldController.text) ?? 20.0;

    // Build Aircraft object with all settings
    Aircraft aircraft = Aircraft(
      tail: tailNumber,
      type: _customIcaoController.text.toUpperCase().trim(),
      wake: _customWake,
      icao: _customModeSController.text.toUpperCase().trim(),
      equipment: _customEquipmentController.text.toUpperCase().trim(),
      cruiseTas: _customCruiseTasController.text.trim(),
      surveillance: _customSurveillanceController.text.toUpperCase().trim(),
      fuelEndurance: _customFuelEnduranceController.text.trim(),
      color: _customColorController.text.toUpperCase().trim(),
      pic: _customPicController.text.toUpperCase().trim(),
      picInfo: _customPicInfoController.text.toUpperCase().trim(),
      sinkRate: _customSinkRateController.text.trim(),
      fuelBurn: usableFuel > 0 && _customCruiseEntries.isNotEmpty 
          ? _customCruiseEntries.first.gph.toStringAsFixed(1) : '',
      base: _customBaseController.text.toUpperCase().trim(),
      other: _customOtherController.text.toUpperCase().trim(),
      icon: _customIcon,
      maxGrossWeight: maxWeight,
      usableFuel: usableFuel,
      emptyWeight: emptyWeight,
      takeoffData: jsonEncode({
        'entries': _customTakeoffEntries.map((e) => e.toMap()).toList(),
        'headwindPct': toHeadwindPct,
        'tailwindPct': toTailwindPct,
        'softFieldPct': toSoftFieldPct,
      }),
      landingData: jsonEncode({
        'entries': _customLandingEntries.map((e) => e.toMap()).toList(),
        'headwindPct': ldHeadwindPct,
        'tailwindPct': ldTailwindPct,
        'softFieldPct': ldSoftFieldPct,
      }),
      cruiseData: jsonEncode(_customCruiseEntries.map((e) => e.toMap()).toList()),
    );

    // Build performance data for UI
    List<Performance3DEntry> rawToRoll = _customTakeoffEntries.map((e) => Performance3DEntry(
      altitude: e.altitude, temp: e.temp, weight: e.weight, value: e.groundRoll,
    )).toList();
    
    List<Performance3DEntry> rawTo50 = _customTakeoffEntries.map((e) => Performance3DEntry(
      altitude: e.altitude, temp: e.temp, weight: e.weight, value: e.over50ft,
    )).toList();
    
    List<Performance3DEntry> rawLdRoll = _customLandingEntries.map((e) => Performance3DEntry(
      altitude: e.altitude, temp: e.temp, weight: e.weight, value: e.groundRoll,
    )).toList();
    
    List<Performance3DEntry> rawLd50 = _customLandingEntries.map((e) => Performance3DEntry(
      altitude: e.altitude, temp: e.temp, weight: e.weight, value: e.over50ft,
    )).toList();
    
    List<Cruise3DEntry> rawCruise = _customCruiseEntries.map((e) => Cruise3DEntry(
      altitude: e.altitude.toDouble(), temp: e.temp.toDouble(),
      powerPercent: e.powerPercent.toDouble(), ktas: e.ktas, gph: e.gph,
    )).toList();

    AircraftPerformanceData custom = AircraftPerformanceData(
      name: tailNumber,
      icaoType: aircraft.type,
      maxGrossWeight: maxWeight,
      usableFuel: usableFuel,
      emptyWeight: emptyWeight,
      takeoffGroundRoll: _buildDummyTable(),
      takeoffOver50ft: _buildDummyTable(),
      landingGroundRoll: _buildDummyTable(),
      landingOver50ft: _buildDummyTable(),
      cruiseTable: CruisePerformanceTable(entries: []),
      rawTakeoffRollEntries: rawToRoll,
      rawTakeoff50ftEntries: rawTo50,
      rawLandingRollEntries: rawLdRoll,
      rawLanding50ftEntries: rawLd50,
      rawCruiseEntries: rawCruise,
      takeoffHeadwindPct: toHeadwindPct,
      takeoffTailwindPct: toTailwindPct,
      takeoffSoftFieldPct: toSoftFieldPct,
      landingHeadwindPct: ldHeadwindPct,
      landingTailwindPct: ldTailwindPct,
      landingSoftFieldPct: ldSoftFieldPct,
    );

    setState(() {
      _customAircraft.add(custom);
      _showCustomEntry = false;
      _selectedAircraft = custom;
    });

    _saveCustomAircraftToDb(aircraft);
    _saveSelectedAircraft();
    _loadWnbForAircraft();
    _resetCustomForm();
  }
  
  void _resetCustomForm() {
    _customNameController.clear();
    _customIcaoController.clear();
    _customMaxWeightController.text = '2400';
    _customUsableFuelController.text = '48';
    _customEmptyWeightController.text = '1500';
    _customToHeadwindController.text = '1.5';
    _customToTailwindController.text = '10.0';
    _customToSoftFieldController.text = '15';
    _customLdHeadwindController.text = '1.5';
    _customLdTailwindController.text = '10.0';
    _customLdSoftFieldController.text = '20';
    _customWake = 'LIGHT';
    _customIcon = 'plane';
    _customColorController.clear();
    _customModeSController.clear();
    _customPicController.clear();
    _customPicInfoController.clear();
    _customBaseController.clear();
    _customEquipmentController.text = 'S';
    _customSurveillanceController.text = 'N';
    _customOtherController.clear();
    _customCruiseTasController.clear();
    _customFuelEnduranceController.clear();
    _customSinkRateController.clear();
  }

  Widget _buildCruiseTableCard() {
    List<CruiseTableEntry> entries = _selectedAircraft.cruiseTable.entries;
    int targetAlt = int.tryParse(_cruiseAltitudeController.text) ?? 8000;
    
    Set<int> altitudes = entries.map((e) => e.altitude).toSet();
    List<int> sortedAlts = altitudes.toList()..sort();
    
    int displayAlt = targetAlt;
    if (!altitudes.contains(targetAlt) && sortedAlts.isNotEmpty) {
      displayAlt = sortedAlts.reduce((a, b) => (a - targetAlt).abs() < (b - targetAlt).abs() ? a : b);
    }
    
    List<CruiseTableEntry> atAlt = entries.where((e) => e.altitude == displayAlt).toList();
    atAlt.sort((a, b) => b.percentPower.compareTo(a.percentPower));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'POH Cruise Table @ $displayAlt ft',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            if (sortedAlts.length > 1) ...[
              const SizedBox(height: 8),
              Text('Available altitudes: ${sortedAlts.join(", ")} ft',
                   style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
            ],
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  children: const [
                    Padding(padding: EdgeInsets.all(8), child: Text('Power', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    Padding(padding: EdgeInsets.all(8), child: Text('KTAS', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    Padding(padding: EdgeInsets.all(8), child: Text('GPH', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  ],
                ),
                ...atAlt.map((s) => TableRow(
                  children: [
                    Padding(padding: const EdgeInsets.all(8), child: Text('${s.percentPower}%', textAlign: TextAlign.center)),
                    Padding(padding: const EdgeInsets.all(8), child: Text('${s.ktas.round()}', textAlign: TextAlign.center)),
                    Padding(padding: const EdgeInsets.all(8), child: Text(s.gph.toStringAsFixed(1), textAlign: TextAlign.center)),
                  ],
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPohNoteCard() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Values interpolated from POH performance tables. Always verify with your actual POH.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAircraftSpecsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Current Aircraft Specs',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_selectedAircraft.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            _buildSpecRow('Max Gross Weight', '${_selectedAircraft.maxGrossWeight.round()} lbs'),
            _buildSpecRow('Usable Fuel', '${_selectedAircraft.usableFuel.round()} gal'),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPowerSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Power Setting: $_cruisePowerPercent%'),
        Slider(
          value: _cruisePowerPercent.toDouble(),
          min: 45,
          max: 85,
          divisions: 8,
          label: '$_cruisePowerPercent%',
          onChanged: (value) {
            setState(() {
              _cruisePowerPercent = value.round();
            });
          },
        ),
      ],
    );
  }

  Widget _buildResultCard(String title, IconData icon, List<_ResultRow> results, Color statusColor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 24, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...results.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(r.label, style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: r.bold ? FontWeight.bold : FontWeight.normal,
                  )),
                  Text(
                    r.value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: r.bold ? FontWeight.bold : FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard(String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {TextInputType? keyboard, String? tooltip}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          suffixIcon: tooltip != null ? Tooltip(
            showDuration: const Duration(seconds: 30),
            triggerMode: TooltipTriggerMode.tap,
            message: tooltip,
            child: const Icon(Icons.info_outline, size: 20),
          ) : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
  
  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
  
  Widget _buildWakeDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _customWake,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Wake Turbulence',
          isDense: true,
        ),
        items: ['LIGHT', 'MEDIUM', 'HEAVY'].map((w) => DropdownMenuItem(
          value: w,
          child: Text(w),
        )).toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() => _customWake = value);
          }
        },
      ),
    );
  }
  
  Widget _buildIconDropdown() {
    const List<String> iconTypes = ['plane', 'helicopter', 'canard'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Aircraft Icon',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _customIcon,
            isDense: true,
            isExpanded: true,
            items: iconTypes.map((iconType) => DropdownMenuItem<String>(
              value: iconType,
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/$iconType.png',
                    width: 28,
                    height: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(iconType.substring(0, 1).toUpperCase() + iconType.substring(1)),
                ],
              ),
            )).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _customIcon = value);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ResultRow {
  final String label;
  final String value;
  final bool bold;

  _ResultRow(this.label, this.value, {this.bold = false});
}
