import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';

class OpenAipDatabaseHelper {
  static final OpenAipDatabaseHelper _instance = OpenAipDatabaseHelper._internal();
  static Database? _database;

  OpenAipDatabaseHelper._internal();

  factory OpenAipDatabaseHelper() {
    return _instance;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final avarexDir = Directory(p.join(documentsDirectory.path, 'avarex'));

    if (!avarexDir.existsSync()) {
      await avarexDir.create(recursive: true);
    }

    final path = p.join(avarexDir.path, 'openaip.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await _createTables(db);
      },
    );
  }

  // These Tables and Columns need to match main.db structure, update if main.db get's changed
  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE airports (
        LocationID TEXT,
        DLID TEXT,
        FaaID TEXT,
        ARPLatitude REAL,
        ARPLongitude REAL,
        Type TEXT,
        FacilityName TEXT,
        Use TEXT,
        FSSPhone TEXT,
        Manager TEXT,
        ManagerPhone TEXT,
        ARPElevation TEXT,
        MagneticVariation TEXT,
        TrafficPatternAltitude TEXT,
        FuelTypes TEXT,
        Customs TEXT,
        Beacon TEXT,
        LightSchedule TEXT,
        SegCircle TEXT,
        ATCT TEXT,
        UNICOMFrequencies TEXT,
        CTAFFrequency TEXT,
        NonCommercialLandingFee TEXT,
        State TEXT,
        City TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE airportrunways (
        DLID TEXT,
        Length TEXT,
        Width TEXT,
        Surface TEXT,
        LEIdent TEXT,
        HEIdent TEXT,
        LELatitude TEXT,
        HELatitude TEXT,
        LELongitude TEXT,
        HELongitude TEXT,
        LEElevation TEXT,
        HEElevation TEXT,
        LEHeadingT TEXT,
        HEHeading TEXT,
        LEDT TEXT,
        HEDT TEXT,
        LELights TEXT,
        HELights TEXT,
        LEILS TEXT,
        HEILS TEXT,
        LEVGSI TEXT,
        HEVGSI TEXT,
        LEPattern TEXT,
        HEPattern TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE airportfreq (
        DLID TEXT,
        Type TEXT,
        Freq TEXT
      );
    ''');
  }

  Future<Database> _createTemporaryDatabase(String tempDbName) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final tempDbPath = p.join(documentsDirectory.path, '$tempDbName.db');

    return await openDatabase(
      tempDbPath,
      version: 1,
      onCreate: (db, version) async {
        await _createTables(db);
      },
    );
  }

  Future<void> deleteTemporaryDatabase(String dbName) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final tempDbPath = p.join(documentsDirectory.path, '$dbName.db');

    try {
      final tempDb = await openDatabase(tempDbPath);
      await tempDb.close();
    } catch (e) {
      throw Exception('Error closing database: $e');
    }

    final tempDbFile = File(tempDbPath);
    if (await tempDbFile.exists()) {
      await tempDbFile.delete();
    }
  }

  Future<void> _loadJsonIntoTempDb(Database tempDb, String filePath) async {
    final jsonString = await File(filePath).readAsString();
    final dynamic jsonData = jsonDecode(jsonString);

    if (jsonData == null) throw Exception("Invalid JSON data!");

    if (jsonData is List<dynamic>) {
      for (final item in jsonData) {
        if (item is Map<String, dynamic>) {
          await _insertAirport(item, tempDb);
        }
      }
    } else if (jsonData is Map<String, dynamic>) {
      await _insertAirport(jsonData, tempDb);
    } else {
      throw Exception("Invalid JSON structure: Expected Map or List.");
    }
  }

  Future<String> checkDatabaseState(String filePath) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final openAipDbPath = p.join(documentsDirectory.path, 'avarex', 'openaip.db');

    // Ensure the main database exists
    final openAipDbFile = File(openAipDbPath);
    if (!await openAipDbFile.exists()) {
      return 'Database Not Found';
    }

    const tempDbName = 'tempopenaip';
    final tempDb = await _createTemporaryDatabase(tempDbName);
    final openAipDb = await openDatabase(openAipDbPath);

    try {
      // Load JSON data into the temporary database
      await _loadJsonIntoTempDb(tempDb, filePath);

      // Query IDs from temp DB and compare with openaip.db
      final tempAirports = await tempDb.rawQuery('SELECT DLID FROM airports');
      for (final row in tempAirports) {
        final dlid = row['DLID'] as String?;
        if (dlid != null) {
          final match = await openAipDb.rawQuery(
              'SELECT DLID FROM airports WHERE DLID = ?', [dlid]);
          if (match.isEmpty) {
            return 'Database Out of Date - Missing Airport Data';
          }
        }
      }

      final tempRunways = await tempDb.rawQuery('SELECT DLID FROM airportrunways');
      for (final row in tempRunways) {
        final dlid = row['DLID'] as String?;
        if (dlid != null) {
          final match = await openAipDb.rawQuery(
              'SELECT DLID FROM airportrunways WHERE DLID = ?', [dlid]);
          if (match.isEmpty) {
            return 'Database Out of Date - Missing Runway Data';
          }
        }
      }

      final tempFreqs = await tempDb.rawQuery('SELECT DLID FROM airportfreq');
      for (final row in tempFreqs) {
        final dlid = row['DLID'] as String?;
        if (dlid != null) {
          final match = await openAipDb.rawQuery(
              'SELECT DLID FROM airportfreq WHERE DLID = ?', [dlid]);
          if (match.isEmpty) {
            return 'Database Out of Date - Missing Frequency Data';
          }
        }
      }

      return 'Data already up-to-date';
    } finally {
      await tempDb.close();
      await deleteTemporaryDatabase(tempDbName);
    }
  }

  Future<bool> isDlidInDatabase(String dlid) async {
    final db = await database;
    final result = await db.query(
      'airports',
      where: 'DLID = ?',
      whereArgs: [dlid],
    );
    return result.isNotEmpty;
  }

  Future<String> saveToDatabase(String filePath) async {
    try {
      final db = await database;
      final jsonString = await File(filePath).readAsString();
      final dynamic jsonData = jsonDecode(jsonString);

      if (jsonData == null) throw Exception("Invalid JSON data!");

      if (jsonData is List<dynamic>) {
        for (final item in jsonData) {
          if (item is Map<String, dynamic>) {
            await _processAirportData(item, db);
          } else {
            throw Exception("Invalid JSON structure in array.");
          }
        }
        return 'Data saved';
      } else if (jsonData is Map<String, dynamic>) {
        await _processAirportData(jsonData, db);
        return 'Data saved';
      } else {
        throw Exception("Invalid JSON structure: Expected Map or List.");
      }
    } catch (e) {
      throw Exception("Failed to save to database: $e");
    }
  }

  Future<void> _processAirportData(Map<String, dynamic> airportData, Database db) async {
    final dlid = airportData['_id']?.toString() ?? '';
    final existing = await db.query('airports', where: 'DLID = ?', whereArgs: [dlid]);

    if (existing.isNotEmpty) {
      final isSame = _isDataIdentical(existing.first, airportData);
      if (!isSame) {
        await _updateAirport(airportData, db);
      }
    } else {
      await _insertAirport(airportData, db);
    }
  }

  Future<void> _insertAirport(Map<String, dynamic> airportData, Database db) async {
    final batch = db.batch();

    final airport = _buildAirportData(airportData);
    batch.insert('airports', airport, conflictAlgorithm: ConflictAlgorithm.replace);

    final airportLatitude = (airportData['geometry']?['coordinates']?[1] as num?)?.toDouble() ?? 0.0;
    final airportLongitude = (airportData['geometry']?['coordinates']?[0] as num?)?.toDouble() ?? 0.0;
    final airportElevation = (airportData['elevation']?['value'] as num?)?.toDouble() ?? 0.0;

    final runways = (airportData['runways'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final pairedRunways = buildRunwayPairs(
      runways,
      airportData['_id'],
      airportLatitude,
      airportLongitude,
      airportElevation, 
    );

    for (final runway in pairedRunways) {
      batch.insert('airportrunways', runway);
    }

    final frequencies = (airportData['frequencies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final freq in frequencies) {
      batch.insert('airportfreq', _buildFrequencyData(freq, airportData['_id'] ?? ''));
    }

    await batch.commit(noResult: true);
  }

  Future<void> _updateAirport(Map<String, dynamic> airportData, Database db) async {
    final batch = db.batch();

    final airport = _buildAirportData(airportData);
    batch.update(
      'airports',
      airport,
      where: 'DLID = ?',
      whereArgs: [airportData['_id']?.toString() ?? ''],
    );

    batch.delete('airportrunways', where: 'DLID = ?', whereArgs: [airportData['_id']?.toString() ?? '']);

    final airportLatitude = (airportData['geometry']?['coordinates']?[1] as num?)?.toDouble() ?? 0.0;
    final airportLongitude = (airportData['geometry']?['coordinates']?[0] as num?)?.toDouble() ?? 0.0;
    final airportElevation = (airportData['elevation']?['value'] as num?)?.toDouble() ?? 0.0;

    final runways = (airportData['runways'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final pairedRunways = buildRunwayPairs(
      runways,
      airportData['_id'],
      airportLatitude,
      airportLongitude,
      airportElevation, 
    );

    for (final runway in pairedRunways) {
      batch.insert('airportrunways', runway);
    }

    batch.delete('airportfreq', where: 'DLID = ?', whereArgs: [airportData['_id']?.toString() ?? '']);
    final frequencies = (airportData['frequencies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final freq in frequencies) {
      batch.insert('airportfreq', _buildFrequencyData(freq, airportData['_id'] ?? ''));
    }

    await batch.commit(noResult: true);
  }

  bool _isDataIdentical(Map<String, dynamic> existing, Map<String, dynamic> incoming) {
    final incomingFlattened = _buildAirportData(incoming);

    for (final key in incomingFlattened.keys) {
      final existingValue = existing[key]?.toString() ?? '';
      final incomingValue = incomingFlattened[key]?.toString() ?? '';

      if (existingValue != incomingValue) {
        return false;
      }
    }
    return true;
  }

  // Parse OpenAIP JSON for OpenAIP DB
  Map<String, String> _buildAirportData(Map<String, dynamic> data) {
    const double metersToFeet = 3.28084;

    final Map<int, String> airportTypes = {
      0: 'AIRPORT',
      1: 'GLIDERPORT',
      2: 'AIRPORT', // Assuming this is 'Airfield Civil'
      3: 'AIRPORT', // International Airport
      4: 'HELIPORT',
      5: 'HELIPORT', // Military Aerodrome
      6: 'ULTRALIGHT',
      7: 'HELIPORT', // Civil Heliport
      8: 'AIRPORT', // Closed Aerodrome
      9: 'AIRPORT', // IFR Airport
      10: 'SEAPLANE BAS', // Water Airfield
      11: 'AIRPORT', // Landing Strip
      12: 'AIRPORT', // Agricultural Landing Strip
      13: 'AIRPORT', // Altiport
    };

    final Map<int, String> fuelTypes = {
      0: 'Super PLUS',
      1: 'AVGAS',
      2: 'Jet A',
      3: 'Jet A1',
      4: 'Jet B',
      5: 'Diesel',
      6: 'AVGAS UL91',
    };

    final frequencies = (data['frequencies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    final unicomFreq = frequencies
        .firstWhere((f) => f['type'] == 12, orElse: () => {})['value']
        ?.toString() ?? '';

    final ctafFreq = frequencies
        .firstWhere((f) => f['type'] == 4, orElse: () => {})['value']
        ?.toString() ?? '';

    final dlid = data['_id']?.toString() ?? '';
    final locationId = data['icaoCode']?.toString() ??
        'UNKNOWN-${dlid.isNotEmpty && dlid.length >= 4 ? dlid.substring(dlid.length - 4) : 'XXXX'}';

    return {
      'LocationID': locationId, // data['icaoCode']?.toString() ?? 'UNKNOWN',
      'DLID': data['_id']?.toString() ?? '',
      'FaaID': data['iataCode']?.toString() ?? '',
      'ARPLatitude': data['geometry']?['coordinates']?[1]?.toString() ?? '',
      'ARPLongitude': data['geometry']?['coordinates']?[0]?.toString() ?? '',
      'Type': airportTypes[data['type']] ?? '',
      'FacilityName': data['name']?.toString() ?? '',
      'Use': data['private'] == true ? 'Private' : 'Public',
      'FSSPhone': '',
      'Manager': data['contact']?.toString() ?? '',
      'ManagerPhone': (data['telephoneServices'] as List<dynamic>? ?? []).isNotEmpty
          ? data['telephoneServices'][0]['phoneNumber']?.toString() ?? ''
          : '',
      'ARPElevation': (((data['elevation']?['value'] as num?) ?? 0) * metersToFeet).toStringAsFixed(1),
      'MagneticVariation': data['magneticDeclination']?.toString() ?? '',
      'TrafficPatternAltitude': '',
      'FuelTypes': (data['services']?['fuelTypes'] as List<dynamic>? ?? [])
          .map((f) => fuelTypes[f] ?? 'Unknown')
          .join(', '),
      'Customs': data['services']?['passengerFacilities']?.contains(2) == true ? 'Yes' : 'No',
      'Beacon': '',
      'LightSchedule': '',
      'SegCircle': '',
      'ATCT': data['ppr'] == true ? 'Yes' : 'No',
      'UNICOMFrequencies': unicomFreq,
      'CTAFFrequency': ctafFreq,
      'NonCommercialLandingFee': '',
      'State': data['country']?.toString() ?? '',
      'City': '',
    };
  }

  Map<String, String> _buildRunwayData(
    Map<String, dynamic> leEntry,
    Map<String, dynamic>? heEntry,
    String dlid,
    double airportLatitude,
    double airportLongitude,
    double airportElevation,
    int offset, // Passed offset for parallel runways
  ) {
    const double metersToFeet = 3.28084;

    final Map<int, String> runwaySurfaces = {
      0: 'ASPH',
      1: 'CONC',
      2: 'TURF',
      3: 'SAND',
      4: 'SAND',
      5: 'ASPH',
      6: 'CONC',
      7: 'ASPH',
      8: 'CONC',
      9: 'SAND',
      10: 'DIRT',
      11: 'DIRT',
      12: 'DIRT',
      13: 'TURF',
      14: 'DIRT',
      15: 'DIRT',
      16: 'DIRT',
      17: 'CONC',
      18: 'SAND',
      19: 'CONC',
      20: 'CONC',
      21: 'ASPH',
      22: 'DIRT',
    };

    final String surface = leEntry['surface']?['mainComposite'] != null
        ? runwaySurfaces[leEntry['surface']['mainComposite']] ?? ''
        : '';

    final int heading = int.tryParse(leEntry['trueHeading']?.toString() ?? '') ??
        _calculateHeadingFromDesignator(leEntry['designator'], heEntry?['designator']);

    final Map<String, String> leThreshold = _calculateThreshold(
      entry: leEntry,
      airportLatitude: airportLatitude,
      airportLongitude: airportLongitude,
      runwayLength: leEntry['dimension']?['length']?['value'] ?? 0,
      heading: heading,
      offset: offset,
      isHighEnd: true,
    );

    final Map<String, String> heThreshold = _calculateThreshold(
      entry: heEntry,
      airportLatitude: airportLatitude,
      airportLongitude: airportLongitude,
      runwayLength: leEntry['dimension']?['length']?['value'] ?? 0,
      heading: heading,
      offset: offset,
      isHighEnd: false,
    );

    final String lengthInFeet = ((leEntry['dimension']?['length']?['value'] ?? 0) * metersToFeet).toStringAsFixed(1);
    final String widthInFeet = ((leEntry['dimension']?['width']?['value'] ?? 0) * metersToFeet).toStringAsFixed(1);
    final String leElevationInFeet = ((leEntry['thresholdLocation']?['elevation']?['value'] ?? airportElevation) * metersToFeet)
        .toStringAsFixed(1);
    final String heElevationInFeet = ((heEntry?['thresholdLocation']?['elevation']?['value'] ?? airportElevation) * metersToFeet)
        .toStringAsFixed(1);

    return {
      'DLID': dlid,
      'Length': lengthInFeet,
      'Width': widthInFeet,
      'Surface': surface,
      'LEIdent': leEntry['designator']?.toString() ?? '',
      'LELatitude': leThreshold['latitude'] ?? '',
      'LELongitude': leThreshold['longitude'] ?? '',
      'LEElevation': leElevationInFeet,
      'LEHeadingT': heading.toString(),
      'HEIdent': heEntry?['designator']?.toString() ?? '',
      'HELatitude': heThreshold['latitude'] ?? '',
      'HELongitude': heThreshold['longitude'] ?? '',
      'HEElevation': heElevationInFeet,
      'HEHeading': ((heading + 180) % 360).toString(),
      'LELights': '',
      'LEILS': '',
      'LEPattern': '',
      'LEDT': '',
      'HEDT': '',
      'LEVGSI': '',
      'HEVGSI': '',
      'HELights': '',
      'HEILS': '',
      'HEPattern': '',
    };
  }

  Map<String, String> _buildFrequencyData(Map<String, dynamic> data, String dlid) {
    final Map<int, String> frequencyTypes = {
      0: 'Approach',
      1: 'Apron',
      2: 'Arrival',
      3: 'Center',
      4: 'CTAF',
      5: 'CD/P', //'Delivery',
      6: 'Departure',
      7: 'FIS',
      8: 'Gliding',
      9: 'GND/P', //'Ground',
      10: 'Information',
      11: 'Multicom',
      12: 'UNICOM',
      13: 'Radar',
      14: 'LCL/P', //'Tower',
      15: 'ATIS',
      16: 'Radio',
      17: 'Other',
      18: 'AIRMET',
      19: 'AWOS',
      20: 'Lights',
      21: 'VOLMET',
      22: 'AFIS',
    };

    return {
      'DLID': dlid,
      'Type': frequencyTypes[data['type']] ?? '',
      'Freq': data['value']?.toString() ?? '',
    };
  }

  // OpenAIP misses a lot of data so we need calculate if it's missing. 
  // Use aipport location as midpoint for runways, calculate runway ends coordinates from the runway headings
  // This is just an estimate based on what data we have and to display runways in AvareX
  Map<String, String> _calculateThreshold({
    required Map<String, dynamic>? entry,
    required double airportLatitude,
    required double airportLongitude,
    required int runwayLength,
    required int heading,
    required int offset, 
    bool isHighEnd = false,
  }) {
    final Distance distance = Distance();

    // Base threshold calculation
    final LatLng airportCoordinates = LatLng(airportLatitude, airportLongitude);
    final adjustedHeading = (heading + (isHighEnd ? 180 : 0)) % 360;

    final LatLng baseThreshold = distance.offset(
      airportCoordinates,
      runwayLength / 2.0,
      adjustedHeading.toDouble(),
    );

    // Determine the **shared perpendicular heading** for the entire runway
    final int perpendicularHeading = (offset > 0)
        ? (heading + 90) % 360 // Offset right
        : (heading - 90 + 360) % 360; // Offset left

    final LatLng offsetThreshold = distance.offset(
      baseThreshold,
      offset.abs().toDouble(),
      perpendicularHeading.toDouble(),
    );

    return {
      'latitude': offsetThreshold.latitude.toStringAsFixed(6),
      'longitude': offsetThreshold.longitude.toStringAsFixed(6),
    };
  }

  int _calculateHeadingFromDesignator(String? leDesignator, String? heDesignator) {
    if (leDesignator == null && heDesignator == null) return 0;

    final leHeading = int.tryParse(leDesignator?.replaceAll(RegExp(r'[LCR]$'), '') ?? '');
    final heHeading = int.tryParse(heDesignator?.replaceAll(RegExp(r'[LCR]$'), '') ?? '');

    if (leHeading != null) return (leHeading * 10) % 360;
    if (heHeading != null) return (heHeading * 10 + 180) % 360;

    return 0;
  }

  // Runways in OpenAIP have a seperate runway per heading, we need to determine which runways are the same and combine for use in AvareX main.db
  List<Map<String, String>> buildRunwayPairs(
    List<Map<String, dynamic>> runways,
    String dlid,
    double airportLat,
    double airportLon,
    double airportElevation,
  ) {
    final List<Map<String, String>> processedRunways = [];
    final Set<String> processedIds = {};

    final Map<String, int> parallelRunwayOffsets = {};

    for (final leEntry in runways) {
      if (processedIds.contains(leEntry['_id'] ?? '')) continue;

      final Map<String, dynamic> heEntry = runways.firstWhere(
        (e) =>
            e['_id'] != leEntry['_id'] &&
            (e['dimension']?['length']?['value'] ?? '') ==
                (leEntry['dimension']?['length']?['value'] ?? '') &&
            (e['dimension']?['width']?['value'] ?? '') ==
                (leEntry['dimension']?['width']?['value'] ?? ''),
        orElse: () => {},
      );

      processedIds.add(leEntry['_id'] ?? '');
      if (heEntry.isNotEmpty) processedIds.add(heEntry['_id'] ?? '');

      final String leIdent = _toNumber(leEntry['designator']?.toString());
      final String heIdent = _toNumber(heEntry['designator']?.toString());
      final String parallelKey = '${dlid}_${leIdent}_$heIdent';

      final int offset = parallelRunwayOffsets.containsKey(parallelKey)
          ? parallelRunwayOffsets[parallelKey]! + 75 
          : 75;
      parallelRunwayOffsets[parallelKey] = offset;

      final runwayData = _buildRunwayData(
        leEntry,
        heEntry,
        dlid,
        airportLat,
        airportLon,
        airportElevation,
        offset,
      );

      processedRunways.add(runwayData);
    }

    return processedRunways;
  }

  String _toNumber(String? designator) {
    if (designator == null) return '';
    // Remove all letters (L, R, C) and keep only numbers
    return designator.replaceAll(RegExp(r'[^\d]'), '');
  }

  Future<void> removeFromDatabase(String filePath) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final avarexDir = p.join(documentsDirectory.path, 'avarex');

    final fileName = p.basename(filePath); 
    final countryFolder = filePath.contains(p.separator)
        ? p.dirname(filePath).split(p.separator).last
        : filePath.split('_').first;

    final fullFilePath = p.join(avarexDir, countryFolder, fileName);

    if (!await File(fullFilePath).exists()) {
      throw Exception('JSON file not found at path: $fullFilePath');
    }

    final openAipDbPath = p.join(avarexDir, 'openaip.db');

    if (!await File(openAipDbPath).exists()) {
      throw Exception('OpenAIP database does not exist!');
    }

    final openAipDb = await database;
    const tempDbName = 'tempopenaip';

    final tempDb = await _createTemporaryDatabase(tempDbName);

    try {
      await _loadJsonIntoTempDb(tempDb, fullFilePath);

      final batch = openAipDb.batch();

      final runwayDlidsToDelete = await tempDb.rawQuery('SELECT DLID FROM airportrunways');
      for (final row in runwayDlidsToDelete) {
        final dlid = row['DLID'] as String;
        batch.delete('airportrunways', where: 'DLID = ?', whereArgs: [dlid]);
      }

      final freqDlidsToDelete = await tempDb.rawQuery('SELECT DLID FROM airportfreq');
      for (final row in freqDlidsToDelete) {
        final dlid = row['DLID'] as String;
        batch.delete('airportfreq', where: 'DLID = ?', whereArgs: [dlid]);
      }

      final airportDlidsToDelete = await tempDb.rawQuery('SELECT DLID FROM airports');
      for (final row in airportDlidsToDelete) {
        final dlid = row['DLID'] as String;
        batch.delete('airports', where: 'DLID = ?', whereArgs: [dlid]);
      }

      await batch.commit(noResult: true);

    } finally {
      await tempDb.close();
      await deleteTemporaryDatabase(tempDbName);
    }
  }

  Future<void> removeCountryData(String countryCode) async {
    final db = await database;
    final dlids = await db.query('airports', columns: ['DLID'], where: 'State = ?', whereArgs: [countryCode]);

    final batch = db.batch();
    for (final dlidRow in dlids) {
      final dlid = dlidRow['DLID'] as String?;
      if (dlid != null) {
        batch.delete('airports', where: 'DLID = ?', whereArgs: [dlid]);
        batch.delete('airportrunways', where: 'DLID = ?', whereArgs: [dlid]);
        batch.delete('airportfreq', where: 'DLID = ?', whereArgs: [dlid]);
      }
    }
    await batch.commit(noResult: true);
  }
}
