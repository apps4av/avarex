import 'dart:io';

import 'package:avaremp/data/main_database_helper.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path/path.dart' as path;


class PathUtils {

  // do not delete tiles below level 8
  static final RegExp _expNoDelete = RegExp(r"^tiles/[0-9]*/[0-7]/.*");

  static final RegExp _expCsup = RegExp(r"^(ne_)|^(nc_)|^(_nw)|^(se_)|^(sc_)|^(sw_)|^(ec_)|^(ak_)|^(pac_)");

  static final RegExp _expAlt = RegExp(
      r"^(PAC\d*TO.*)|^(PAC\d*ALT.*)|"
      r"^(EC\d*TO.*)|^(EC\d*ALT.*)|"
      r"^(AK\d*TO.*)|^(AK\d*ALT.*)|"
      r"^(NE\d*TO.*)|^(NE\d*ALT.*)|^(NC\d*TO.*)|^(NC\d*ALT.*)|^(NW\d*TO.*)|^(NW\d*ALT.*)|"
      r"^(SE\d*TO.*)|^(SE\d*ALT.*)|^(SC\d*TO.*)|^(SC\d*ALT.*)|^(SW\d*TO.*)|^(SW\d*ALT.*)"
  );

  static String getLocalFilePath(String base, String filename) {
    return path.join(base, "$filename.zip");
  }

  static String getUnzipFilePath(String base, String filename) {
    return path.join(base, filename);
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

  static String getFilePath(String base, String file) {
    String id = path.join(base, file);
    return(id);
  }

  static String getMinimumsFilePath(String base, String name) {
    String afd = path.join(base, "minimums");
    String filename = path.join(afd, "${name[0]}/$name.png");
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

  static String filename(String url) {
    return path.split(url).last;
  }

  static Future<List<String>> getDocumentsNames(String base) async {
    List<String> ret = [];
    try {
      final d = Directory(base);
      final List<FileSystemEntity> entities = await d.list().toList();
      for (FileSystemEntity en in entities) {
        if(isTextFile(en.path) || isPdfFile(en.path) || isKmlFile(en.path)) {
          ret.add(en.path);
        }
      }
    }
    catch(e) {
      ret = [];
    }
    return(ret);
  }

  static bool isTextFile(String url) {
    return path.extension(url) == ".txt";
  }

  static bool isPdfFile(String url) {
    return path.extension(url) == ".pdf";
  }

  static bool isKmlFile(String url) {
    return path.extension(url) == ".kml";
  }

  static Future<void> writeTrack(String base, String data) async {
    DateTime now = DateTime.now();
    try {
      final format = DateFormat('yyyy_MMMM_dd@kk_mm_ss').format(now);
      final String file = path.join(base, "track_$format.kml");
      final File f = File(file);
      await f.writeAsString(data);
    }
    catch(e) {}
  }

  static Future<List<String>> getPlatesAndCSupSorted(String base, String airport) async {
    List<String> plates = [];
    List<String> csup = [];
    List<String> alternates = [];

    plates = await PathUtils.getPlateNames(base, airport);
    csup = await MainDatabaseHelper.db.findCsup(airport);
    alternates = await MainDatabaseHelper.db.findAlternates(airport);

    // combine plates and csup
    plates.addAll(csup);
    plates.addAll(alternates);
    plates = plates.toSet().toList();
    plates.sort((a,b) {
      if(a == "AIRPORT-DIAGRAM") return -1;
      if(b == "AIRPORT-DIAGRAM") return 1;
      if(_expCsup.hasMatch(a)) return -1;
      if(_expCsup.hasMatch(b)) return 1;
      if(_expAlt.hasMatch(a)) return -1;
      if(_expAlt.hasMatch(b)) return 1;
      if(a.startsWith("HOT-SPOT")) return -1;
      if(b.startsWith("HOT-SPOT")) return 1;
      if(a.startsWith("LAHSO")) return -1;
      if(b.startsWith("LAHSO")) return 1;
      return a.compareTo(b);

    });
    return(plates);
  }

  static String getPlatePath(String base, String airport, String name) {

    // this should be simplified in server code. Just put CSUP and minimums in each airport where it belongs
    String path = getPlateFilePath(base, airport, name);

    if(_expCsup.hasMatch(name)) {
      return getCSupFilePath(base, name);
    }

    if(_expAlt.hasMatch(name)) {
      return getMinimumsFilePath(base, name);
    }

    return(path);
  }

  static bool shouldNotDelete(String name) {
    return _expNoDelete.hasMatch(name);
  }

  static void deleteFile(String url) {
    File f = File(url);
    f.delete();
  }

}
