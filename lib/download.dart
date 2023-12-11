import 'dart:convert';
import 'dart:core';
import 'dart:io';

import 'package:avaremp/faa_dates.dart';
import 'package:avaremp/path_utils.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_archive/flutter_archive.dart';
import 'package:http/http.dart' as http;
import 'chart.dart';

class Download {

  String _currentCycle = "";
  static const String _server = "https://www.apps4av.org/new/";
  bool _cancelDownloadAndDelete = false;

  Future<void> _deleteZipFile(File file) async {
    try {
      await file.delete();
    }
    catch (e) {
    }
  }

  void cancel() {
    _cancelDownloadAndDelete = true;
  }
  
  String _getUrlOfRemoteFile(String filename) {
    return "$_server/$_currentCycle/$filename.zip";
  }

  Future<String> getChartCycleLocal(Chart chart) async {
    String dir = await PathUtils.getDownloadDirPath();
    try {
      String version = await File(path.join(dir, chart.filename))
          .openRead()
          .map(utf8.decode)
          .transform(const LineSplitter()).elementAt(0);
      return version;
    }
    catch(e) {
      return "";
    }
  }

  Future<bool> isChartExpired(Chart chart) async {
    //update chart instance to reflect state on disk

    String current = FaaDates.getCurrentCycle();
    String version = await getChartCycleLocal(chart);

    return current != version;
  }

  Future<void> delete(Chart chart, Function(Chart, double)? callback) async {
    _cancelDownloadAndDelete = false;
    callback!(chart, 0); // start

    String dir = await PathUtils.getDownloadDirPath();
    String file = path.join(dir, chart.filename);

    List<String> s;
    try {
      s = await File(file).readAsLines(); // list of files to delete from manifest
    }
    catch(e) {
      callback(chart, -1);
      return;
    }

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
      if(_cancelDownloadAndDelete) {
        callback(chart, -1);
        return;
      }
      progress = index / s.length;
      if (progress - lastProgress >= 0.01) { // 1% change min
        callback(chart, progress);
        lastProgress = progress;
      }
    }
    await _deleteZipFile(File(file));

    callback(chart, 1); // done
  }

  Future<void> download(Chart chart, Function(Chart, double)? callback) async {
    _cancelDownloadAndDelete = false;
    final Dio dio = Dio();
    double lastProgress = 0;
    File localFile = File(await PathUtils.getLocalFilePath(chart.filename));
    Directory localDir = Directory(await PathUtils.getDownloadDirPath());
    callback!(chart, 0); // download start signal
    CancelToken cancelToken = CancelToken(); // this is to cancel the dio download


    try {
      _currentCycle = await http.read(Uri.parse("$_server/version.php"));
    }
    catch(e) {
      callback(chart, -1); // cycle not known
      return;
    }

    // start fresh
    await _deleteZipFile(localFile);

    // this generate shows progress event to UI
    void showDownloadProgress(received, total) {
      if(_cancelDownloadAndDelete) {
        cancelToken.cancel();
      }
      if (total != -1) {
        double progress = received / total * 0.5; // 0 to 0.5 for download
        if (progress - lastProgress >= 0.01) { // 1% change min
          callback(chart, progress);
          lastProgress = progress;
        }
      }
    }

    try {
      Response response = await dio.get(
        _getUrlOfRemoteFile(chart.filename),
        onReceiveProgress: showDownloadProgress,
        cancelToken: cancelToken,
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
      callback(chart, 0.5); // unzip start
    } catch (e) {
      callback(chart, -1);
    }

    try {
      await ZipFile.extractToDirectory(
          zipFile: localFile,
          destinationDir: localDir,
          onExtracting: (zipEntry, pg) {
            double progress = 0.5 + (pg / 200); // 0.50 to 1 for unzip
            if (progress - lastProgress >= 0.01) {
              callback(chart, progress);
              lastProgress = progress;
            }
            if(_cancelDownloadAndDelete) {
              callback(chart, -1);
              return ZipFileOperation.cancel;
            }
            return ZipFileOperation.includeItem;
          });
      callback(chart, 1); // done
    } catch (e) {
      callback(chart, -1);
    }

    // clean up
    await _deleteZipFile(localFile);

  }
}

