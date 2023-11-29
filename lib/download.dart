import 'dart:core';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_archive/flutter_archive.dart';
import 'package:http/http.dart' as http;

class Download {



  String cycle = "";
  static String server = "https://www.apps4av.org/new/";

  static int stateInit = 0;
  static int stateDone = 100;
  static int stateFailed = -1;

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

  Future<void> download(String filename, Function(String, int)? callback) async {
    final Dio dio = Dio();
    int lastProgress = 0;
    File localFile = File(await getLocalFilePath(filename));
    Directory localDir = Directory(await getDownloadDirPath());

    cycle = await http.read(Uri.parse("$server/version.php"));
    print(cycle);

    // start fresh
    await deleteZipFile(localFile);

    // this generate shows progress event to UI
    void showDownloadProgress(received, total) {
      if (total != -1) {
        int progress = ((received / total) * 100).round();
        if (progress - lastProgress > 0) {
          callback!(filename, progress);
          lastProgress = progress;
        }
      }
    }

    try {
      Response response = await dio.get(
        getUrlOfRemoteFile(filename),
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
      callback!(filename, stateFailed);
    }

    lastProgress = 0;
    try {
      await ZipFile.extractToDirectory(
          zipFile: localFile,
          destinationDir: localDir,
          onExtracting: (zipEntry, progress) {
            int intp = progress.round();
            if (intp - lastProgress > 0) {
              callback!(filename, intp);
              lastProgress = intp;
            }
            return ZipFileOperation.includeItem;
          });
    } catch (e) {
      callback!(filename, stateFailed);
    }


    // clean up
    await deleteZipFile(localFile);



  }
}

