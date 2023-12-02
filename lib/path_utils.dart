import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;


class PathUtils {
  static Future<String> getDownloadDirPath() async {
    Directory dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<String> getLocalFilePath(filename) async {
    String dir = await getDownloadDirPath();
    return path.join(dir, "$filename.zip");
  }

  static Future<String> getPlateFilePath(String airport, String plate) async {
    String dir = await getDownloadDirPath();
    String plates = path.join(dir, "plates");
    String id = path.join(plates, airport);
    String filename = path.join(id, "$plate.png");
    return(filename);
  }

}
