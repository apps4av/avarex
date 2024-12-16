import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'openaip_database_helper.dart';
import 'main_database_helper.dart';

class OpenAipDbSyncHelper {
  static final OpenAipDbSyncHelper _instance = OpenAipDbSyncHelper._internal();
  static Database? _openAipDb;
  static Database? _mainDb;
  Timer? _syncTimer;

  OpenAipDbSyncHelper._internal();

  factory OpenAipDbSyncHelper() => _instance;

  Future<void> initializeDatabases() async {
    _openAipDb ??= await OpenAipDatabaseHelper().database;
    _mainDb ??= await MainDatabaseHelper.db.database;

    if (_openAipDb == null || _mainDb == null) {
      return;
    }

    // Create necessary tables if not present
    await _openAipDb!.execute('''
      CREATE TABLE IF NOT EXISTS openaip_shadow_airports (DLID TEXT PRIMARY KEY)
    ''');
    await _openAipDb!.execute('''
      CREATE TABLE IF NOT EXISTS openaip_shadow_runways (DLID TEXT PRIMARY KEY)
    ''');
    await _openAipDb!.execute('''
      CREATE TABLE IF NOT EXISTS openaip_shadow_freqs (DLID TEXT PRIMARY KEY)
    ''');
    await _openAipDb!.execute('''
      CREATE TABLE IF NOT EXISTS openaip_sync_status (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        synced INTEGER NOT NULL CHECK (synced IN (0, 1))
      )
    ''');

    // Ensure the sync status table has a row
    final count = Sqflite.firstIntValue(
      await _openAipDb!.rawQuery('SELECT COUNT(*) FROM openaip_sync_status')
    );
    if (count == 0) {
      await _openAipDb!.insert('openaip_sync_status', {'synced': 0});
    }

    await syncShadowTables();
  }

  // The Shadow Tables keep track of the DLIDs so we can keep openaip.db synced with main.db even when data is removed from openaip.db
  Future<void> syncShadowTables() async {
    if (_openAipDb == null) {
      throw Exception('OpenAIP database is not initialized.');
    }

    final batch = _openAipDb!.batch();

    final openAipAirports = await _openAipDb!.query('airports', columns: ['DLID']);
    for (var row in openAipAirports) {
      batch.insert('openaip_shadow_airports', {'DLID': row['DLID']}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final openAipRunways = await _openAipDb!.query('airportrunways', columns: ['DLID']);
    for (var row in openAipRunways) {
      batch.insert('openaip_shadow_runways', {'DLID': row['DLID']}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final openAipFreqs = await _openAipDb!.query('airportfreq', columns: ['DLID']);
    for (var row in openAipFreqs) {
      batch.insert('openaip_shadow_freqs', {'DLID': row['DLID']}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    try {
      await batch.commit(noResult: true);
    } catch (e) {
      throw Exception('Error committing batch in syncShadowTables: $e');
    }
  }

  Future<bool> isSyncFlagSet() async {
    if (_openAipDb == null) {
      throw Exception('OpenAIP database is not initialized.');
    }
    final result = await _openAipDb!.query(
      'openaip_sync_status',
      columns: ['synced'],
      limit: 1,
    );
    return result.isNotEmpty && result.first['synced'] == 1;
  }

  Future<void> setSyncFlag(bool synced) async {
    if (_openAipDb == null) {
      throw Exception('OpenAIP database is not initialized.');
    }
    await _openAipDb!.update(
      'openaip_sync_status',
      {'synced': synced ? 1 : 0},
      where: 'id = 1',
    );
  }

  Future<bool> isInSync() async {
    if (_openAipDb == null || _mainDb == null) {
      return false;
    }

    if (!await isSyncFlagSet()) {
      return false;
    }

    // Check if openaip.db has any data at all
    final openaipTableNames = ['airports', 'airportrunways', 'airportfreq'];
    for (final tableName in openaipTableNames) {
      final count = Sqflite.firstIntValue(
        await _openAipDb!.rawQuery('SELECT COUNT(*) FROM $tableName')
      );
      if (count == null || count == 0) {
        return false;
      }
    }

    // Fetch DLIDs from shadow tables
    final shadowAirports = await _openAipDb!.query('openaip_shadow_airports', columns: ['DLID']);
    final shadowRunways = await _openAipDb!.query('openaip_shadow_runways', columns: ['DLID']);
    final shadowFreqs = await _openAipDb!.query('openaip_shadow_freqs', columns: ['DLID']);

    final shadowAirportDlids = shadowAirports.map((row) => row['DLID'] as String).toSet();
    final shadowRunwayDlids = shadowRunways.map((row) => row['DLID'] as String).toSet();
    final shadowFreqDlids = shadowFreqs.map((row) => row['DLID'] as String).toSet();

    // Fetch DLIDs from openaip tables
    final openaipAirports = await _openAipDb!.query('airports');
    final openaipRunways = await _openAipDb!.query('airportrunways');
    final openaipFreqs = await _openAipDb!.query('airportfreq');

    final openaipAirportDlids = openaipAirports.map((row) => row['DLID'] as String).toSet();
    final openaipRunwayDlids = openaipRunways.map((row) => row['DLID'] as String).toSet();
    final openaipFreqDlids = openaipFreqs.map((row) => row['DLID'] as String).toSet();

    // Check for stale data (shadow but not in openaip)
    final staleAirportDlids = shadowAirportDlids.difference(openaipAirportDlids);
    final staleRunwayDlids = shadowRunwayDlids.difference(openaipRunwayDlids);
    final staleFreqDlids = shadowFreqDlids.difference(openaipFreqDlids);

    // Check if stale data exists in main.db
    for (final table in [
      {'name': 'airports', 'dlids': staleAirportDlids},
      {'name': 'airportrunways', 'dlids': staleRunwayDlids},
      {'name': 'airportfreq', 'dlids': staleFreqDlids},
    ]) {
      final dlids = table['dlids'] as Set<String>;
      if (dlids.isNotEmpty) {
        final result = await _mainDb!.query(
          table['name'] as String,
          where: 'DLID IN (${List.filled(dlids.length, '?').join(',')})',
          whereArgs: dlids.toList(),
        );
        if (result.isNotEmpty) {
          return false;
        }
      }
    }

    // Check for missing data (openaip but not in main.db)
    for (final table in [
      {'name': 'airports', 'data': openaipAirports},
      {'name': 'airportrunways', 'data': openaipRunways},
      {'name': 'airportfreq', 'data': openaipFreqs},
    ]) {
      final rows = table['data'] as List<Map<String, Object?>>;
      for (final row in rows) {
        final result = await _mainDb!.query(
          table['name'] as String,
          where: row.keys.map((key) => '$key = ?').join(' AND '),
          whereArgs: row.values.toList(),
        );
        if (result.isEmpty) {
          return false;
        }
      }
    }

    // If no stale or missing data, we are in sync
    return true;
  }

  // Add all OpenAIP Data
  Future<void> addOpenAipToMainDb() async {
    if (_openAipDb == null || _mainDb == null) {
      throw Exception('Databases are not initialized.');
    }

    final batch = _mainDb!.batch();

    final openAipAirports = await _openAipDb!.query('airports');
    for (var row in openAipAirports) {
      batch.insert('airports', row, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final openAipRunways = await _openAipDb!.query('airportrunways');
    for (var row in openAipRunways) {
      batch.insert('airportrunways', row, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final openAipFreqs = await _openAipDb!.query('airportfreq');
    for (var row in openAipFreqs) {
      batch.insert('airportfreq', row, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await batch.commit(noResult: true);
    await setSyncFlag(true);
    enableSync();
  }

  // Removes all OpenAIP Data
  Future<void> removeOpenAipFromMainDb() async {
    if (_openAipDb == null || _mainDb == null) {
      throw Exception('Databases are not initialized.');
    }

    final shadowAirports = await _openAipDb!.query('openaip_shadow_airports', columns: ['DLID']);
    final shadowRunways = await _openAipDb!.query('openaip_shadow_runways', columns: ['DLID']);
    final shadowFreqs = await _openAipDb!.query('openaip_shadow_freqs', columns: ['DLID']);

    final batch = _mainDb!.batch();

    for (final row in shadowAirports) {
      batch.delete('airports', where: 'DLID = ?', whereArgs: [row['DLID']]);
    }

    for (final row in shadowRunways) {
      batch.delete('airportrunways', where: 'DLID = ?', whereArgs: [row['DLID']]);
    }

    for (final row in shadowFreqs) {
      batch.delete('airportfreq', where: 'DLID = ?', whereArgs: [row['DLID']]);
    }

    await batch.commit(noResult: true);
    await setSyncFlag(false);
    disableSync();
  }

  void startAutoSync(Duration interval) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) async {
      final syncEnabled = await isSyncFlagSet();
      if (syncEnabled) {
        await syncShadowTables();
        if (!(await isInSync())) {
          await syncRemoveFromMainDb();
          await syncAddToMainDb();
        }
      }
    });
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  void disableSync() {
    stopAutoSync();
  }

  void enableSync() {
    startAutoSync(const Duration(seconds: 30));
  }

  Future<void> manualSync() async {
    final syncEnabled = await isSyncFlagSet();
    if (syncEnabled) {
      await syncShadowTables();
      if (!await isInSync()) {
        await syncRemoveFromMainDb();
        await syncAddToMainDb();
      }
    }
  }

  // Only add new OpenAIP Data
  Future<void> syncAddToMainDb() async {
    if (_openAipDb == null || _mainDb == null) {
      throw Exception('Databases are not initialized.');
    }
  
    final batch = _mainDb!.batch();
  
    final mainAirports = await _mainDb!.query('airports');
    final openaipAirports = await _openAipDb!.query('airports');
    for (final row in openaipAirports) {
      if (!mainAirports.any((mainRow) => _rowsMatch(mainRow, row))) {
        batch.insert('airports', row, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  
    final mainRunways = await _mainDb!.query('airportrunways');
    final openaipRunways = await _openAipDb!.query('airportrunways');
    for (final row in openaipRunways) {
      if (!mainRunways.any((mainRow) => _rowsMatch(mainRow, row))) {
        batch.insert('airportrunways', row, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  
    final mainFreqs = await _mainDb!.query('airportfreq');
    final openaipFreqs = await _openAipDb!.query('airportfreq');
    for (final row in openaipFreqs) {
      if (!mainFreqs.any((mainRow) => _rowsMatch(mainRow, row))) {
        batch.insert('airportfreq', row, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  
    await batch.commit(noResult: true);
  }
  
  /// Compares two rows and returns true if all columns match
  bool _rowsMatch(Map<String, Object?> row1, Map<String, Object?> row2) {
    if (row1.keys.length != row2.keys.length) {
      return false;
    }
  
    for (final key in row1.keys) {
      if (row1[key] != row2[key]) {
        return false;
      }
    }
  
    return true;
  }

  // Removes Data from main.db that doesn't exist in openaip.db 
  Future<void> syncRemoveFromMainDb() async {
    if (_openAipDb == null || _mainDb == null) {
      throw Exception('Databases are not initialized.');
    }

    final shadowAirports = await _openAipDb!.query('openaip_shadow_airports', columns: ['DLID']);
    final shadowRunways = await _openAipDb!.query('openaip_shadow_runways', columns: ['DLID']);
    final shadowFreqs = await _openAipDb!.query('openaip_shadow_freqs', columns: ['DLID']);

    final batch = _mainDb!.batch();

    final openaipAirports = await _openAipDb!.query('airports', columns: ['DLID']);
    final openaipRunways = await _openAipDb!.query('airportrunways', columns: ['DLID']);
    final openaipFreqs = await _openAipDb!.query('airportfreq', columns: ['DLID']);

    final shadowAirportDlids = shadowAirports.map((row) => row['DLID'] as String).toSet();
    final openaipAirportDlids = openaipAirports.map((row) => row['DLID'] as String).toSet();
    final missingAirportDlids = shadowAirportDlids.difference(openaipAirportDlids);

    final shadowRunwayDlids = shadowRunways.map((row) => row['DLID'] as String).toSet();
    final openaipRunwayDlids = openaipRunways.map((row) => row['DLID'] as String).toSet();
    final missingRunwayDlids = shadowRunwayDlids.difference(openaipRunwayDlids);

    final shadowFreqDlids = shadowFreqs.map((row) => row['DLID'] as String).toSet();
    final openaipFreqDlids = openaipFreqs.map((row) => row['DLID'] as String).toSet();
    final missingFreqDlids = shadowFreqDlids.difference(openaipFreqDlids);

    for (final dlid in missingAirportDlids) {
      batch.delete('airports', where: 'DLID = ?', whereArgs: [dlid]);
    }

    for (final dlid in missingRunwayDlids) {
      batch.delete('airportrunways', where: 'DLID = ?', whereArgs: [dlid]);
    }

    for (final dlid in missingFreqDlids) {
      batch.delete('airportfreq', where: 'DLID = ?', whereArgs: [dlid]);
    }

    await batch.commit(noResult: true);
  }
}
