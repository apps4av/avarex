import 'dart:core';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_archive/flutter_archive.dart';
import 'package:http/http.dart' as http;

import 'download_list.dart';

class Download {



  String cycle = "";
  static String server = "https://www.apps4av.org/new/";

  Future<void> deleteZipFile(File file) async {
    try {
      await file.delete();
    }
    catch (e) {
    }
  }

  int getCurrentCycle() {
    DateTime now = DateTime.now();
    DateTime epoch = DateTime.utc(2001, 1, 4);
    int daysSinceEpoch = now.difference(epoch).inDays;
    int cycle = (daysSinceEpoch / 28).floor() + 1;
    return cycle;
  }

  Future<String> getDownloadDirPath() async {
    Directory dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> getLocalFilePath(filename) async {
    String dir = await getDownloadDirPath();
    return path.join(dir, "$filename.zip");
  }

  String getUrlOfRemoteFile(String filename) {
    return "$server/$cycle/$filename.zip";
  }

  Future<void> getChartStatus(Chart chart) async {
    //update chart instance to reflect state on disk
  }

  Future<void> delete(Chart chart, Function(Chart, double)? callback) async {
    String dir = await getDownloadDirPath();
    String file = path.join(dir, chart.filename);
    List<String> s = await File(file).readAsLines();
    double progress = 0;
    double lastProgress = 0;
    for(int index = 1; index < s.length; index++) { // skip version
      File f = File(path.join(dir, s[index]));
      try {
        await f.delete(recursive: true);
      }
      catch(e) {
        continue; // try all
      }
      progress = index / s.length;
      if (progress - lastProgress >= 0.01) { // 1% change min
        callback!(chart, progress);
        lastProgress = progress;
      }
    }
    // delete the main file
    try {
      await File(file).delete();
    }
    catch(e) {
    }
  }


  Future<void> download(Chart chart, Function(Chart, double)? callback) async {
    final Dio dio = Dio();
    double lastProgress = 0;
    File localFile = File(await getLocalFilePath(chart.filename));
    Directory localDir = Directory(await getDownloadDirPath());

    cycle = await http.read(Uri.parse("$server/version.php"));

    // start fresh
    await deleteZipFile(localFile);

    // this generate shows progress event to UI
    void showDownloadProgress(received, total) {
      if (total != -1) {
        double progress = received / total * 0.5; // 0 to 0.5 for download
        if (progress - lastProgress >= 0.01) { // 1% change min
          callback!(chart, progress);
          lastProgress = progress;
        }
      }
    }

    try {
      Response response = await dio.get(
        getUrlOfRemoteFile(chart.filename),
        onReceiveProgress: showDownloadProgress,
        //Received data with List<int>
        options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            validateStatus: (status) {
              return status! < 500;
            }
        ),
      );
      var raf = localFile.openSync(mode: FileMode.write);
      // response.data is List<int> type
      raf.writeFromSync(response.data);
      await raf.close();
    } catch (e) {
      callback!(chart, -1);
    }

    try {
      await ZipFile.extractToDirectory(
          zipFile: localFile,
          destinationDir: localDir,
          onExtracting: (zipEntry, progress) {
            progress = 0.5 + (progress / 200); // 0.50 to 1 for unzip
            if (progress - lastProgress >= 0.01) {
              callback!(chart, progress);
              lastProgress = progress;
            }
            return ZipFileOperation.includeItem;
          });
    } catch (e) {
      callback!(chart, -1);
    }

    // clean up
    //await deleteZipFile(localFile);

  }
}

