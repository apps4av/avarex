import 'dart:io';

import 'package:avaremp/main_database_helper.dart';
import 'package:path/path.dart';
import 'package:path/path.dart' as path;


class PathUtils {

  static String getLocalFilePath(String base, String filename) {
    return path.join(base, "$filename.zip");
  }

  static String getPlateFilePath(String base, String airport, String plate) {
    String plates = path.join(base, "plates");
    String id = path.join(plates, airport);
    String filename = path.join(id, "$plate.png");
    return(filename);
  }

  static String getCSupFilePath(String base, String csup) {
    String afd = path.join(base, "afd");
    String filename = path.join(afd, "$csup.png");
    return(filename);
  }

  static Future<List<String>> getPlateNames(String base, String airport) async {
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

  static Future<List<String>> getPlatesAndCSupSorted(String base, String airport) async {
    List<String> plates = [];
    List<String> csup = [];

    plates = await PathUtils.getPlateNames(base, airport);
    csup = await MainDatabaseHelper.db.findCsup(airport);

    // combine plates and csup
    for(String c in csup) {
      plates.add("CSUP:$c");
    }
    plates = plates.toSet().toList();
    plates.sort();
    return(plates);
  }

  static String getPlatePath(String base, String airport, String name) {
    String path = PathUtils.getPlateFilePath(base, airport, name);
    if(name.startsWith("CSUP:")) {
      // all CSUP plates are appended by CSUP so remove it
      path = PathUtils.getCSupFilePath(base, name.replaceFirst("CSUP:", ""));
    }
    return(path);
  }

}
