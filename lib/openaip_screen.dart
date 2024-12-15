import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'data/openaip_database_helper.dart';
import 'data/openaip_db_sync_helper.dart';

class OpenAipScreen extends StatefulWidget {
  const OpenAipScreen({Key? key}) : super(key: key);

  @override
  _OpenAipScreenState createState() => _OpenAipScreenState();
}

class _OpenAipScreenState extends State<OpenAipScreen> {
  String? dbPath;
  bool dbExists = false;
  bool isLoading = false;
  bool hasOpenAipData = false;

  final Map<String, String> countries = {
    'us': 'United States',
    'ca': 'Canada',
    'gb': 'United Kingdom',
    'de': 'Germany',
    'fr': 'France',
    'au': 'Australia',
    'nz': 'New Zealand',
  };

  final Map<String, String> fileDescriptions = {
    'apt': 'Airport Data',
    'asp': 'Airspace Data',
    'hot': 'Hotspot Data',
    'hgl': 'Hang Gliding Sites',
    'nav': 'Navaids Data',
    'obs': 'Obstacles Data',
    'rpp': 'Reporting Points',
  };

  String? selectedCountry;
  List<Map<String, dynamic>> countryFiles = [];
  final TextEditingController isoController = TextEditingController();

  final OpenAipDatabaseHelper _dbHelper = OpenAipDatabaseHelper();

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
    _checkDatabase();
    _loadCachedCountries();
    _checkSyncStatus();
    _checkOpenAipData();
  }

  Future<void> _initializeDatabase() async {
    await _dbHelper.database;
  }

  void _setLoading(bool loading) {
    if (mounted) {
      setState(() {
        isLoading = loading;
      });
    }
  }

  // Check for main.db and contents 
  Future<void> _checkDatabase() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final avarexDir = Directory(p.join(directory.path, 'avarex'));

      if (!avarexDir.existsSync()) {
        await avarexDir.create(recursive: true);
      }

      final mainDbPath = p.join(avarexDir.path, 'main.db');
      final dbExistsOnDisk = await databaseExists(mainDbPath);
      bool hasTables = false;

      if (dbExistsOnDisk) {
        final mainDb = await openDatabase(mainDbPath);
        try {
          final tables = await mainDb.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
          hasTables = tables.isNotEmpty;
        } catch (e) {
          debugPrint('Error checking tables: $e');
        } 
      }

      if (mounted) {
        setState(() {
          dbPath = avarexDir.path;
          this.dbExists = dbExistsOnDisk && hasTables;
        });
      }

      if (!dbExistsOnDisk || !hasTables) {
        _showDownloadDialog();
      }
    } catch (e) {
      debugPrint('Error checking database: $e');
      if (mounted) {
        setState(() {
          dbExists = false;
        });
        _showDownloadDialog();
      }
    }
  }

  Future<void> _loadCachedCountries() async {
    final cacheFile = await _getCacheFile();
    if (await cacheFile.exists()) {
      final cachedData = jsonDecode(await cacheFile.readAsString());
      setState(() {
        countries.addAll(Map<String, String>.from(cachedData));
      });
    }
  }

  Future<void> _addCountryToCache(String isoCode, String countryName) async {
    countries[isoCode] = countryName;
    final cacheFile = await _getCacheFile();
    await cacheFile.writeAsString(jsonEncode(countries));
  }

  Future<File> _getCacheFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, 'countries_cache.json'));
  }

  // Instead of listing every country, use restcountries API
  Future<String?> _fetchCountryName(String isoCode) async {
    try {
      final response = await http.get(
          Uri.parse('https://restcountries.com/v3.1/alpha/$isoCode'));
      if (response.statusCode == 200) {
        final countryData = jsonDecode(response.body);
        return countryData[0]['name']['common'];
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  void _onIsoCodeSubmitted(String isoCode) async {
    isoCode = isoCode.toLowerCase();
    if (isoCode.length != 2) {
      _showMessage('Invalid ISO code. Must be 2 letters.');
      return;
    }

    if (countries.containsKey(isoCode)) {
      setState(() {
        selectedCountry = isoCode;
      });
    } else {
      final countryName = await _fetchCountryName(isoCode) ?? 'Unknown Country';
      setState(() {
        countries[isoCode] = countryName;
        selectedCountry = isoCode;
      });
      await _addCountryToCache(isoCode, countryName);
    }
  }

  void _showDownloadDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Database Not Found'),
        content: const Text(
            'The main database file (main.db) is missing. Please download it from the Downloads section first.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/download');
            },
            child: const Text('Go to Downloads'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCountryFiles(String countryCode) async {
    _setLoading(true);
    try {
      if (dbPath == null) return;
      final countryDir = Directory(p.join(dbPath!, countryCode));
      if (countryDir.existsSync()) {
        final files = countryDir
            .listSync()
            .whereType<File>()
            .map((file) => {
                  'name': p.basename(file.path),
                  'path': file.path,
                  'description': fileDescriptions[
                      p.basename(file.path).split('_')[1].split('.')[0]] ?? '',
                })
            .toList();

        for (final file in files) {
          final filePath = file['path'] as String;
          final state = await _dbHelper.checkDatabaseState(filePath);
          file['state'] = state;
        }

        setState(() {
          countryFiles = files;
        });
      } else {
        setState(() {
          countryFiles = [];
        });
      }

      // Status check
      _checkDatabase();
      _checkSyncStatus();
      _checkOpenAipData();
    } finally {
      _setLoading(false);
    }
  }

  // Download full JSON datasets from OpenAIP rather than using API
  Future<void> _downloadJson(String countryCode, String fileType) async {
    if (dbPath == null) return;

    _setLoading(true);
    try {
      final countryDir = Directory(p.join(dbPath!, countryCode));
      if (!countryDir.existsSync()) {
        countryDir.createSync(recursive: true);
      }

      final fileName = '${countryCode}_$fileType.json';
      final tempFileName = '${countryCode}_$fileType.temp.json';
      final filePath = p.join(countryDir.path, fileName);
      final tempFilePath = p.join(countryDir.path, tempFileName);
      final url =
          'https://storage.googleapis.com/29f98e10-a489-4c82-ae5e-489dbcd4912f/$fileName';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final tempFile = File(tempFilePath);
        await tempFile.writeAsBytes(response.bodyBytes);

        final existingFile = File(filePath);
        final fileExists = existingFile.existsSync();

        final checkState = await _dbHelper.checkDatabaseState(tempFilePath);

        if (checkState == 'Data already up-to-date' && fileExists) {
          tempFile.deleteSync();
          _showMessage('$fileName is already up-to-date. Downloaded file discarded.');
        } else if (checkState == 'Data already up-to-date' && !fileExists) {
          tempFile.renameSync(filePath);
          _showMessage('$fileName was missing and has been restored.');
        } else {
          if (fileExists) {
            final backupPath =
                p.join(countryDir.path, '${countryCode}_${fileType}_old.json');
            existingFile.renameSync(backupPath);
          }

          tempFile.renameSync(filePath);
          await _dbHelper.removeFromDatabase(filePath);
          await _saveToDatabase(filePath);

          _showMessage('$fileName downloaded and database updated successfully.');
        }

        _loadCountryFiles(countryCode);
      } else {
        throw Exception('Failed to download file: ${response.reasonPhrase}');
      }
    } finally {
      await OpenAipDbSyncHelper().manualSync();
      _setLoading(false);
    }
  }

  // Save to the OpenAIP DB 
  Future<void> _saveToDatabase(String filePath) async {
    _setLoading(true);
    try {
      final message = await _dbHelper.saveToDatabase(filePath);
      _showMessage(message);
      _loadCountryFiles(selectedCountry!);
    } catch (e) {
      _showMessage('Failed to save data to database: $e');
    } finally {
      await OpenAipDbSyncHelper().manualSync();
      _setLoading(false);
    }
  }

  // Remove from OpenAIP DB
  Future<void> _removeFromDatabase(String dlid) async {
    _setLoading(true);
    try {
      await _dbHelper.removeFromDatabase(dlid);
      _showMessage('Data removed from database successfully!');
      _loadCountryFiles(selectedCountry!);
    } catch (e) {
      _showMessage('Failed to remove data from database: $e');
    } finally {
      await OpenAipDbSyncHelper().manualSync();
      _setLoading(false);
    }
  }

  void _deleteFile(String filePath) async {
    _setLoading(true);
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
        _showMessage('File deleted successfully!');
      } else {
        _showMessage('File does not exist!');
      }
      _loadCountryFiles(selectedCountry!);
    } finally {
      _setLoading(false);
    }
  }

  void _deleteCountryFolder(String countryCode) async {
    _setLoading(true);
    try {
      if (dbPath == null) {
        _showMessage('Database path is not available.');
        return;
      }

      final countryDir = Directory(p.join(dbPath!, countryCode));
      if (!countryDir.existsSync()) {
        _showMessage('Country folder does not exist.');
        return;
      }

      final files = countryDir.listSync().whereType<File>();

      for (final file in files) {
        final filePath = file.path;

        final state = await _dbHelper.checkDatabaseState(filePath);

        if (state == 'Data already up-to-date') {
          await _dbHelper.removeFromDatabase(filePath);
        }

        file.deleteSync();
      }

      countryDir.deleteSync();

      _showMessage('All files and database entries for $countryCode have been deleted.');
    } catch (e) {
      _showMessage('Error deleting country folder: $e');
    } finally {
      await OpenAipDbSyncHelper().manualSync();
      _setLoading(false);
    }

    setState(() {
      countryFiles = [];
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool isInSync = false;

  Future<void> _checkSyncStatus() async {
    try {
      final syncHelper = OpenAipDbSyncHelper();
      await syncHelper.initializeDatabases();
      final syncStatus = await syncHelper.isInSync();
      if (mounted) {
        setState(() {
          isInSync = syncStatus;
        });
      }
    } catch (e) {
      debugPrint('Error checking sync status: $e');
      if (mounted) {
        setState(() {
          isInSync = false;
        });
      }
    }
  }

  Future<void> _syncDatabases() async {
    try {
      final syncHelper = OpenAipDbSyncHelper();
      await syncHelper.initializeDatabases();
      await syncHelper.addOpenAipToMainDb();
      await syncHelper.manualSync();
      _showMessage('OpenAIP data synced successfully!');
      _checkSyncStatus();
    } catch (e) {
      _showMessage('Failed to sync OpenAIP data: $e');
    }
  }

  Future<void> _removeOpenAipFromMainDb() async {
    try {
      final syncHelper = OpenAipDbSyncHelper();
      await syncHelper.initializeDatabases();
      await syncHelper.removeOpenAipFromMainDb();
      _showMessage('OpenAIP data removed from main database!');
      _checkSyncStatus();
    } catch (e) {
      _showMessage('Failed to remove OpenAIP data: $e');
    }
  }

  Future<void> _checkOpenAipData() async {
    try {
      final openAipDb = await OpenAipDatabaseHelper().database;

      // Fetch all non-shadow tables
      final tables = await openAipDb.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'openaip_shadow_%' AND name NOT LIKE 'openaip_sync_%'"
      );

      if (tables.isEmpty) {
        setState(() {
          hasOpenAipData = false;
        });
        return;
      }

      bool hasData = false;
      for (var table in tables) {
        final tableName = table['name'] as String?;
        if (tableName != null) {
          final count = Sqflite.firstIntValue(
            await openAipDb.rawQuery('SELECT COUNT(*) FROM $tableName')
          );

          if (count != null && count > 0) {
            hasData = true;
            break; 
          }
        }
      }

      setState(() {
        hasOpenAipData = hasData;
      });
    } catch (e) {
      debugPrint('Error checking OpenAIP data: $e');
      setState(() {
        hasOpenAipData = false; 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OpenAIP')),
      body: Stack(
        children: [
          dbPath == null
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Database Path: $dbPath',
                        style: const TextStyle(fontSize: 16),
                      ),
                      Text(
                        dbExists
                            ? 'Database Status: Available ✅'
                            : 'Database Status: Missing ❌',
                        style: TextStyle(
                          fontSize: 16,
                          color: dbExists ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: isoController,
                        maxLength: 2,
                        decoration: const InputDecoration(
                          labelText: 'Enter ISO Country Code',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: _onIsoCodeSubmitted,
                      ),
                      const SizedBox(height: 16),
                      DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('Select a country'),
                        value: selectedCountry,
                        items: countries.entries
                            .map((entry) => DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedCountry = value;
                            countryFiles = [];
                          });
                          if (value != null) {
                            isoController.text = value;
                            _loadCountryFiles(value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      if (countryFiles.isNotEmpty)
                        Expanded(
                          child: ListView.builder(
                            itemCount: countryFiles.length,
                            itemBuilder: (context, index) {
                              final file = countryFiles[index];
                              final state = file['state'] ?? 'Loading...';
                              final isUpToDate =
                                  state == 'Data already up-to-date';

                              return ListTile(
                                title: Text(file['name']),
                                subtitle: Text(
                                  isUpToDate
                                      ? 'Database Up to Date'
                                      : 'Database Out of Date',
                                  style: TextStyle(
                                    color: isUpToDate
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton(
                                      onPressed: isUpToDate
                                          ? () =>
                                              _removeFromDatabase(file['name'])
                                          : () =>
                                              _saveToDatabase(file['path']),
                                      child: Text(
                                        isUpToDate
                                            ? 'Remove from Database'
                                            : 'Save to Database',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: !isUpToDate
                                          ? () => _deleteFile(file['path'])
                                          : null,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (selectedCountry != null && countryFiles.isNotEmpty)
                        ElevatedButton(
                          onPressed: () =>
                              _deleteCountryFolder(selectedCountry!),
                          child:
                              Text('Delete All Files for $selectedCountry'),
                        ),
                      if (selectedCountry != null)
                        ElevatedButton(
                          onPressed: () =>
                              _downloadJson(selectedCountry!, 'apt'),
                          child: const Text('Download'),
                        ),
                      const SizedBox(height: 16),
                      // Sync Status and Button Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isInSync
                                ? 'OpenAIP Sync Status: In Sync ✅'
                                : 'OpenAIP Sync Status: Out of Sync ❌',
                            style: TextStyle(
                              fontSize: 16,
                              color: isInSync ? Colors.green : Colors.red,
                            ),
                          ),
                          ElevatedButton(
                            onPressed: (hasOpenAipData && isInSync)
                                ? _removeOpenAipFromMainDb
                                : (hasOpenAipData && !isInSync)
                                    ? _syncDatabases
                                    : null, // Disable button if no data
                            child: Text(
                              isInSync
                                  ? 'Remove OpenAIP from AvareX'
                                  : 'Add OpenAIP to AvareX',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
          if (isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
