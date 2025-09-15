import 'dart:io';

import 'package:avaremp/constants.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path/path.dart' as path;


class PathUtils {

  // do not delete tiles below level 8
  static final RegExp _expNoDelete = RegExp(r"^tiles/[0-9]*/[0-7]/.*");

  static final RegExp _expCsup = RegExp(r"^CSUP");

  static String getLocalFilePath(String base, String filename) {
    return path.join(base, "$filename.zip");
  }

  static String getUnzipFilePath(String base, String filename) {
    return path.join(base, filename);
  }

  static String getFilePath(String base, String file) {
    String id = path.join(base, file);
    return(id);
  }

  static String filename(String url) {
    return path.split(url).last;
  }

  static Future<List<String>> getDocumentsNames(String base) async {
    List<String> ret = [];
    try {
      final d = Directory(base);
      final List<FileSystemEntity> entities = await d.list().toList();
      for (FileSystemEntity en in entities) {
        if(isTextFile(en.path) || (isPdfFile(en.path) && Constants.shouldShowPdf) || isKmlFile(en.path) || isJSONFile(en.path) || isPictureFile(en.path)) {
          ret.add(en.path);
        }
      }
    }
    catch(e) {
      ret = [];
    }
    return(ret);
  }

  static bool isJSONFile(String url) {
    return path.extension(url).toLowerCase() == ".geojson";
  }

  static bool isTextFile(String url) {
    return path.extension(url).toLowerCase() == ".txt";
  }

  static bool isPictureFile(String url) {
    return path.extension(url).toLowerCase() == ".gif" ||
        path.extension(url).toLowerCase() == ".webp" ||
        path.extension(url).toLowerCase() == ".bmp" ||
        path.extension(url).toLowerCase() == ".png" ||
        path.extension(url).toLowerCase() == ".jpg" ||
        path.extension(url).toLowerCase() == ".jpeg";
  }

  static bool isPdfFile(String url) {
    return path.extension(url).toLowerCase() == ".pdf";
  }

  static bool isKmlFile(String url) {
    return path.extension(url).toLowerCase() == ".kml";
  }

  static Future<String?> writeTrack(String base, String data) async {
    DateTime now = DateTime.now();
    try {
      final format = DateFormat('yyyy_MMMM_dd@kk_mm_ss').format(now);
      final String file = path.join(base, "track_$format.kml");
      final File f = File(file);
      await f.writeAsString(data);
      return("track_$format.kml");
    }
    catch(e) {
      return(null);
    }
  }

  static String _getPlateFilePath(String base, String airport, String plate) {
    String plates = path.join(base, "plates");
    String id = path.join(plates, airport);
    String filename = path.join(id, "$plate.png");
    return(filename);
  }

  static String _getCsupFilePath(String base, String airport, String plate) {
    String plates = path.join(base, "afd");
    String id = path.join(plates, airport);
    String filename = path.join(id, "$plate.png");
    return(filename);
  }

  static Future<List<String>> _getPlateNames(String base, String airport) async {
    List<String> ret = [];
    try {
      String plates = path.join(base, "plates");
      String id = path.join(plates, airport);
      final d = Directory(id);
      final List<FileSystemEntity> entities = await d.list().toList();
      for (FileSystemEntity en in entities) {
        ret.add(basenameWithoutExtension(en.path));
      }
    }
    catch(e) {
      ret = [];
    }
    return(ret);
  }

  static Future<List<String>> _getCsupNames(String base, String airport) async {
    List<String> ret = [];
    try {
      String plates = path.join(base, "afd");
      String id = path.join(plates, airport);
      final d = Directory(id);
      final List<FileSystemEntity> entities = await d.list().toList();
      for (FileSystemEntity en in entities) {
        ret.add(basenameWithoutExtension(en.path));
      }
    }
    catch(e) {
      ret = [];
    }
    return(ret);
  }


  static Future<List<String>> getPlatesAndCSupSorted(String base, String airportId) async {
    List<String> plates = [];
    List<String> csup = [];

    //XXX: Plates and CSUP are not in ICAO
    String airport = await MainDatabaseHelper.db.getFaaName(airportId);

    plates = await _getPlateNames(base, airport);
    csup = await _getCsupNames(base, airport);
    plates.addAll(csup);

    // combine plates and csup
    plates = plates.toSet().toList();
    plates.sort();
    return(plates);
  }

  static Future<String> getPlatePath(String base, String airportId, String name) async {

    //XXX: Plates and CSUP are not in ICAO
    String airport = await MainDatabaseHelper.db.getFaaName(airportId);

    // this should be simplified in server code. Just put CSUP and minimums in each airport where it belongs
    String path = _getPlateFilePath(base, airport, name);

    if(_expCsup.hasMatch(name)) {
      return _getCsupFilePath(base, airport, name);
    }

    return(path);
  }

  static bool shouldNotDelete(String name) {
    return _expNoDelete.hasMatch(name);
  }

  static Future<void> deleteFile(String url) async {
    File f = File(url);
    await f.delete();
  }


  static Future<String?> getAirportDiagram(String base, String airportId) async {
    List<String> plates = await PathUtils.getPlatesAndCSupSorted(base, airportId);
    if (plates.isNotEmpty && plates[0].contains("AIRPORT DIAGRAM")) {
      return getPlatePath(base, airportId, plates[0]);
    }
    return null;
  }

}


