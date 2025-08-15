import 'dart:convert';
import 'dart:core';
import 'dart:io';

import 'package:async_zip/async_zip.dart';
import 'package:avaremp/faa_dates.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'chart.dart';
import 'package:archive/archive_io.dart';

class Download {

  String _currentCycle = "";
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
  
  String _getUrlOfRemoteFile(String filename, String server) {
    return "$server/$_currentCycle/$filename.zip";
  }

  Future<String> getChartCycleLocal(Chart chart) async {
    String dir = Storage().dataDir;
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

  Future<void> delete(Chart chart, Function(Chart, int)? callback) async {
    _cancelDownloadAndDelete = false;
    if(null != callback) {
      callback(chart, 0); // start
    }

    String dir = Storage().dataDir;
    String file = path.join(dir, chart.filename);

    List<String> s;
    try {
      s = await File(file).readAsLines(); // list of files to delete from manifest
    }
    catch(e) {
      if(null != callback) {
        callback(chart, -1);
      }
      return;
    }

    double progress = 0;
    double lastProgress = 0;

    for(int index = 1; index < s.length; index++) { // skip version
      if(PathUtils.shouldNotDelete(s[index])) {
        // save some files forever
        continue;
      }
      File f = File(path.join(dir, s[index]));
      try {
        await f.delete(recursive: true);
      }
      catch(e) {
        continue; // try all
      }
      if(_cancelDownloadAndDelete) {
        if(null != callback) {
          callback(chart, -1);
        }
        return;
      }
      progress = index / s.length;
      if (progress - lastProgress >= 0.01) { // 1% change min
        if(null != callback) {
          callback(chart, (progress * 100).toInt());
        }
        lastProgress = progress;
      }
    }
    await _deleteZipFile(File(file));

    await Storage().checkChartsExist();
    await Storage().checkDataExpiry();

    if(null != callback) {
      callback(chart, 100); // done
    }
  }

  Future<void> download(Chart chart, bool nextCycle, bool backupServer, Function(Chart, int)? callback) async {

    String server = backupServer ? "https://avare.bubble.org/" : "http://www.apps4av.org/regions/";
    _cancelDownloadAndDelete = false;
    double lastProgress = 0;
    File localFile = File(PathUtils.getLocalFilePath(Storage().dataDir, chart.filename));
    callback!(chart, 0); // download start signal


    try {
      _currentCycle = await http.read(Uri.parse("$server/version.php"));
      if(nextCycle) {
        _currentCycle = FaaDates.getNextCycle(_currentCycle);
      }
    }
    catch(e) {
      callback(chart, -1); // cycle not known
      return;
    }

    // start fresh
    await _deleteZipFile(localFile);

    // this generate shows progress event to UI
    void showDownloadProgress(received, total) {
      if (total != -1) {
        double progress = received / total * 0.5; // 0 to 0.5 for download
        if (progress - lastProgress >= 0.1) { // 10% change min
          callback(chart, (progress * 100).toInt());
          lastProgress = progress;
        }
      }
    }

    try {
      http.Response r = await http.head(Uri.parse(_getUrlOfRemoteFile(chart.filename, server)));
      int total = int.parse(r.headers["content-length"] ?? "0");
      int downloaded = 0;
      final request = http.Request('GET', Uri.parse(_getUrlOfRemoteFile(chart.filename, server)));
      final streamedResponse = await request.send();
      var out = localFile.openWrite();
      await streamedResponse.stream.map((e) {
        downloaded += e.length;
        showDownloadProgress(downloaded, total);
        if(_cancelDownloadAndDelete) {
          throw (Exception("Cancelled"));
        }
        return (e);
      }).pipe(out);
      out.close();
      callback(chart, 50); // unzip start
    }
    catch(e) {
      callback(chart, -1);
    }

    if(_cancelDownloadAndDelete) {
      callback(chart, -1);
      return;
    }

    try {

      if(Platform.isAndroid || Platform.isIOS) { // unzip for low memory devices
        final reader = ZipFileReaderSync();
        try {
          reader.open(File(PathUtils.getLocalFilePath(Storage().dataDir, chart.filename)));

          // Get all Zip entries
          final entries = reader.entries();
          double num = 1;
          for (final entry in entries) {
            if(!entry.isDir) {
              await File(
                  PathUtils.getUnzipFilePath(Storage().dataDir, entry.name))
                  .create(recursive: true); // this creates sub folders
              reader.readToFile(entry.name, File(
                  PathUtils.getUnzipFilePath(Storage().dataDir, entry.name)));
              if (_cancelDownloadAndDelete) {
                callback(chart, -1);
                reader.close();
                return;
              }
            }
            double fraction = num++ / entries.length.toDouble();
            double progress = 0.5 + (fraction / 2); // 0.50 to 1
            if (progress - lastProgress >= 0.1) { // unzip is faster than download
              callback(chart, (progress * 100).toInt());
              lastProgress = progress;
            }
          }
          // Read a specific file
        } on ZipException {
          callback(chart, -1);
        } finally {
          reader.close();
        }
      }
      else {
        final inputStream = InputFileStream(
            PathUtils.getLocalFilePath(Storage().dataDir, chart.filename));
        final archive = ZipDecoder().decodeStream(inputStream);

        double num = 1; // file number being decoded
        for (var file in archive) {
          if (file.isFile) {
            final outputStream = OutputFileStream(
                PathUtils.getUnzipFilePath(Storage().dataDir, file.name));
            file.writeContent(outputStream);
            outputStream.close();
            if (_cancelDownloadAndDelete) {
              callback(chart, -1);
              inputStream.close();
              return;
            }
          }
          double fraction = num++ / archive.length.toDouble();
          double progress = 0.5 + (fraction / 2); // 0.50 to 1
          if (progress - lastProgress >= 0.1) { // unzip is faster than download
            callback(chart, (progress * 100).toInt());
            lastProgress = progress;
          }
        }

        inputStream.close();
      }
      await Storage().checkDataExpiry();
      await Storage().checkChartsExist();
      callback(chart, 100); // done
    } catch (e) {
      callback(chart, -1);
    }

    // clean up
    await _deleteZipFile(localFile);

  }
}

