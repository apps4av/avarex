import 'package:universal_io/io.dart';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'ofm_paths.dart';
import 'ofm_manifest.dart';
import 'ofm_schema.dart';
import 'ofmx_importer.dart';

class OfmDatabaseHelper {
  OfmDatabaseHelper._();

  static final OfmDatabaseHelper db = OfmDatabaseHelper._();
  static Database? _database;

  Future<Database> open(String dataDir) async {
    if (_database != null) {
      return _database!;
    }
    final dbPath = OfmPaths(dataDir).ofmDatabasePath;
    await Directory(path.dirname(dbPath)).create(recursive: true);
    _database = await openDatabase(
      dbPath,
      version: OfmSchema.version,
      onCreate: (database, version) async {
        for (final statement in OfmSchema.createStatements) {
          await database.execute(statement);
        }
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        for (final statement in OfmSchema.createStatements) {
          await database.execute(statement);
        }
      },
    );
    return _database!;
  }

  static Future<void> invalidateConnection() async {
    final database = _database;
    if (database != null) {
      await database.close();
      _database = null;
    }
  }

  String databasePath(String dataDir) => path.normalize(OfmPaths(dataDir).ofmDatabasePath);

  Future<void> recordInstall({
    required String dataDir,
    required OfmInstall install,
    String? effective,
    String? expiration,
    String? ofmxUrl,
    String? mbtilesUrl,
  }) async {
    final database = await open(dataDir);
    await database.insert(
      'ofm_region_install',
      {
        'region': install.region,
        'cycle': install.cycle,
        'effective': effective,
        'expiration': expiration,
        'publication_url': install.publicationUrl.toString(),
        'ofmx_url': ofmxUrl,
        'mbtiles_url': mbtilesUrl,
        'mbtiles_path': install.mbtilesPath,
        'installed_at': install.installedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> importResult({
    required String dataDir,
    required OfmxImportResult result,
    required String region,
    required String cycle,
  }) async {
    final database = await open(dataDir);
    await database.transaction((transaction) async {
      await _deleteRegionCycle(transaction, region, cycle);
      await _insertAll(transaction, 'ofm_airport', result.airports);
      await _insertAll(transaction, 'ofm_airport_comm', result.airportComms);
      await _insertAll(transaction, 'ofm_runway', result.runways);
      await _insertAll(transaction, 'ofm_runway_end', result.runwayEnds);
      await _insertAll(transaction, 'ofm_waypoint', result.waypoints);
      await _insertAll(transaction, 'ofm_airspace', result.airspaces);
      await _insertAll(transaction, 'ofm_airspace_vertex', result.airspaceVertices);
    });
  }

  Future<void> deleteRegion({
    required String dataDir,
    required String region,
    String? cycle,
  }) async {
    final database = await open(dataDir);
    await database.transaction((transaction) async {
      await _deleteRegionCycle(transaction, region, cycle);
      await transaction.delete(
        'ofm_region_install',
        where: cycle == null ? 'region = ?' : 'region = ? and cycle = ?',
        whereArgs: cycle == null ? [region] : [region, cycle],
      );
    });
  }

  static Future<void> _deleteRegionCycle(
    DatabaseExecutor database,
    String region,
    String? cycle,
  ) async {
    final clause = cycle == null ? 'region = ?' : 'region = ? and cycle = ?';
    final args = cycle == null ? <Object?>[region] : <Object?>[region, cycle];
    final airportRows = await database.query('ofm_airport', columns: ['id'], where: clause, whereArgs: args);
    final airportIds = airportRows.map((row) => row['id']).whereType<String>().toList();
    for (final airportId in airportIds) {
      final runwayRows = await database.query('ofm_runway', columns: ['id'], where: 'airport_id = ?', whereArgs: [airportId]);
      for (final row in runwayRows) {
        await database.delete('ofm_runway_end', where: 'runway_id = ?', whereArgs: [row['id']]);
      }
      await database.delete('ofm_runway', where: 'airport_id = ?', whereArgs: [airportId]);
      await database.delete('ofm_airport_comm', where: 'airport_id = ?', whereArgs: [airportId]);
    }
    await database.delete('ofm_airport', where: clause, whereArgs: args);
    await database.delete('ofm_waypoint', where: clause, whereArgs: args);
    final airspaceRows = await database.query('ofm_airspace', columns: ['id'], where: clause, whereArgs: args);
    for (final row in airspaceRows) {
      await database.delete('ofm_airspace_vertex', where: 'airspace_id = ?', whereArgs: [row['id']]);
    }
    await database.delete('ofm_airspace', where: clause, whereArgs: args);
  }

  static Future<void> _insertAll(
    DatabaseExecutor database,
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    for (final row in rows) {
      await database.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
