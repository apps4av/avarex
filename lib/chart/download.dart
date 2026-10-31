import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:isolate';
import 'package:universal_io/io.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/utils/faa_dates.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'chart.dart';
import 'package:archive/archive_io.dart';
// Streaming zip extractor that inflates directly to disk to avoid buffering
// whole files in memory.
import 'chart_extract.dart';

const String _kSetupCancel = 'setupCancel';
const String _kDownloaded = 'downloaded';
const String _kTotal = 'total';
const String _kOk = 'ok';
const String _kProgress = 'progress';
const String _kReply = 'reply';
const String _kZipPath = 'zipPath';
const String _kUrl = 'url';
const String _kDataDir = 'dataDir';
const String _kChartFilename = 'chartFilename';

void _chartDownloadIsolateEntry(Map<String, Object?> start) {
  final SendPort mainSend = start[_kReply]! as SendPort;
  final String zipPath = start[_kZipPath]! as String;
  final String url = start[_kUrl]! as String;
  Future(() async {
    final cancelPort = ReceivePort();
    mainSend.send({_kSetupCancel: cancelPort.sendPort});
    var cancelled = false;
    cancelPort.listen((dynamic m) {
      if (m == true) {
        cancelled = true;
      }
    });
    IOSink? out;
    try {
      final http.Response r = await http.head(Uri.parse(url));
      final int total = int.parse(r.headers["content-length"] ?? "0");
      final request = http.Request('GET', Uri.parse(url));
      final streamedResponse = await request.send();
      if (streamedResponse.statusCode != 200) {
        throw Exception("HTTP ${streamedResponse.statusCode}");
      }
      // size of the body actually being sent (more reliable than the HEAD size)
      final int expected = streamedResponse.contentLength ?? -1;
      out = File(zipPath).openWrite();
      int downloaded = 0;
      double lastProgress = 0;
      await for (final chunk in streamedResponse.stream) {
        if (cancelled) {
          throw Exception("Cancelled");
        }
        downloaded += chunk.length;
        out.add(chunk);
        if (total != -1 && total != 0) {
          final double progress = downloaded / total * 0.5;
          if (progress - lastProgress >= 0.1) {
            mainSend.send({_kDownloaded: downloaded, _kTotal: total});
            lastProgress = progress;
          }
        }
      }
      await out.flush();
      await out.close();
      out = null;
      // A connection that drops early can end the stream without an error;
      // never hand a truncated zip to the extractor.
      if (expected > 0 && downloaded != expected) {
        throw Exception("Incomplete download $downloaded of $expected");
      }
      if (downloaded == 0) {
        throw Exception("Empty download");
      }
      if (await File(zipPath).length() != downloaded) {
        throw Exception("Short write");
      }
      mainSend.send({_kOk: true});
    } catch (e) {
      try {
        await out?.close();
      } catch (_) {}
      try {
        if (await File(zipPath).exists()) {
          await File(zipPath).delete();
        }
      } catch (_) {}
      mainSend.send({_kOk: false});
    } finally {
      cancelPort.close();
    }
  });
}

void _chartUnzipIsolateEntry(Map<String, Object?> start) {
  final SendPort mainSend = start[_kReply]! as SendPort;
  final String dataDir = start[_kDataDir]! as String;
  final String chartFilename = start[_kChartFilename]! as String;
  Future(() async {
    final cancelPort = ReceivePort();
    mainSend.send({_kSetupCancel: cancelPort.sendPort});
    var cancelled = false;
    cancelPort.listen((dynamic m) {
      if (m == true) {
        cancelled = true;
      }
    });
    InputFileStream? inputStream;
    try {
      inputStream = InputFileStream(
          PathUtils.getLocalFilePath(dataDir, chartFilename));
      final archive = ZipDecoder().decodeStream(inputStream);

      // The manifest (named after the chart; it holds the cycle and the list of
      // files to delete) is what marks a chart as installed. Extract it LAST so
      // a cancelled or failed extraction never looks like a complete install.
      final List<ArchiveFile> ordered = <ArchiveFile>[];
      ArchiveFile? manifest;
      for (final ArchiveFile file in archive) {
        if (file.isFile && file.name == chartFilename) {
          manifest = file;
        }
        else {
          ordered.add(file);
        }
      }
      if (manifest != null) {
        ordered.add(manifest);
      }

      double num = 1;
      for (var file in ordered) {
        if (cancelled) {
          inputStream.close();
          mainSend.send({_kOk: false});
          cancelPort.close();
          return;
        }
        if (file.isFile) {
          // Writes to a temp file, verifies size/CRC, then atomically renames.
          // Throws on a truncated/damaged entry (caught below -> failure).
          extractFileStreaming(
              file, PathUtils.getUnzipFilePath(dataDir, file.name));
        }
        final double fraction = num++ / ordered.length.toDouble();
        final double progress = 0.5 + (fraction / 2);
        mainSend.send({_kProgress: progress});
      }

      inputStream.close();
      inputStream = null;
      mainSend.send({_kOk: true});
    } catch (e) {
      try {
        inputStream?.close();
      } catch (_) {}
      mainSend.send({_kOk: false});
    } finally {
      cancelPort.close();
    }
  });
}

class Download {

  bool _cancelDownloadAndDelete = false;
  SendPort? _chartDownloadCancelSendPort;
  SendPort? _chartUnzipCancelSendPort;

  // While chart files (main.db in DatabasesX) are replaced or removed, keep the
  // database closed and block re-opening so it is never touched half written.
  bool _dbReplaceActive = false;

  Future<void> _beginDbReplace() async {
    _dbReplaceActive = true;
    await MainDatabaseHelper.beginReplace();
  }

  Future<void> _endDbReplace() async {
    if (_dbReplaceActive) {
      _dbReplaceActive = false;
      await MainDatabaseHelper.endReplace();
    }
  }

  static Future<void> _deleteZipFile(File file) async {
    bool exists = await file.exists();
    if(exists) {
      try {
        await file.delete();
      }
      catch (e) {
        Storage().setException("Unable to delete file ${file.path}");
      }
    }
  }

  void cancel() {
    _cancelDownloadAndDelete = true;
    _chartDownloadCancelSendPort?.send(true);
    _chartUnzipCancelSendPort?.send(true);
  }

  static Future<String> getChartCycleLocal(Chart chart) async {
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

  static Future<bool> isChartExpired(Chart chart) async {
    //update chart instance to reflect state on disk

    String current = FaaDates.getCurrentCycle();
    String version = await getChartCycleLocal(chart);

    if(version.isEmpty) {
      return false; // not downloaded yet
    }
    if(!chart.check) {
      return false; // static files do not expire
    }

    return current != version;
  }

  Future<void> delete(Chart chart, Function(Chart, int)? callback) async {
    try {
      await _delete(chart, callback);
    }
    finally {
      await _endDbReplace();
    }
  }

  Future<void> _delete(Chart chart, Function(Chart, int)? callback) async {
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

    await _beginDbReplace();

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
      // a leftover -wal/-journal of a deleted database would be replayed into
      // the next database downloaded under the same name
      for(final String side in const ['-wal', '-shm', '-journal']) {
        try {
          final File sf = File(path.join(dir, "${s[index]}$side"));
          if(await sf.exists()) {
            await sf.delete();
          }
        }
        catch(e) { /* best effort */ }
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

    await _endDbReplace();

    if(null != callback) {
      callback(chart, 100); // done
    }
  }

  Future<void> download(Chart chart, bool nextCycle, bool backupServer, Function(Chart, int)? callback) async {
    try {
      await _download(chart, nextCycle, backupServer, callback);
    }
    finally {
      await _endDbReplace();
    }
  }

  Future<void> _download(Chart chart, bool nextCycle, bool backupServer, Function(Chart, int)? callback) async {

    String server = backupServer ? "https://avare.bubble.org/" : "http://www.apps4av.org/regions/";
    _cancelDownloadAndDelete = false;
    _chartDownloadCancelSendPort = null;
    _chartUnzipCancelSendPort = null;
    double lastProgress = 0;
    final String dataDir = Storage().dataDir;
    final String zipPath = PathUtils.getLocalFilePath(dataDir, chart.filename);
    File localFile = File(zipPath);
    callback!(chart, 0); // download start signal

    final String currentCycle = nextCycle
        ? FaaDates.getNextCycle(FaaDates.getCurrentCycle())
        : FaaDates.getCurrentCycle();
    if (currentCycle == "0000") {
      callback(chart, -1); // cycle not known
      return;
    }

    // start fresh
    await _deleteZipFile(localFile);

    if(_cancelDownloadAndDelete) {
      callback(chart, -1);
      return;
    }

    final String downloadUrl = !chart.check
        ? "$server/static/${chart.filename}.zip"
        : "$server/$currentCycle/${chart.filename}.zip";

    final receivePort = ReceivePort();
    final downloadCompleter = Completer<bool>();
    late final StreamSubscription<dynamic> downloadSub;
    downloadSub = receivePort.listen((dynamic message) {
      if (message is! Map) {
        return;
      }
      final map = message.cast<String, Object?>();
      if (map.containsKey(_kSetupCancel)) {
        _chartDownloadCancelSendPort = map[_kSetupCancel] as SendPort;
        return;
      }
      if (map.containsKey(_kDownloaded) && map.containsKey(_kTotal)) {
        final int total = map[_kTotal]! as int;
        if (total != -1) {
          final int downloaded = map[_kDownloaded]! as int;
          final double progress = downloaded / total * 0.5;
          if (progress - lastProgress >= 0.1) {
            callback(chart, (progress * 100).toInt());
            lastProgress = progress;
          }
        }
        return;
      }
      if (map.containsKey(_kOk)) {
        final bool ok = map[_kOk]! as bool;
        if (ok) {
          callback(chart, 50); // unzip start
          downloadCompleter.complete(true);
        } else {
          downloadCompleter.complete(false);
        }
      }
    });

    await Isolate.spawn(
      _chartDownloadIsolateEntry,
      <String, Object?>{
        _kReply: receivePort.sendPort,
        _kZipPath: zipPath,
        _kUrl: downloadUrl,
      },
    );

    final bool downloadOk = await downloadCompleter.future;
    await downloadSub.cancel();
    receivePort.close();
    _chartDownloadCancelSendPort = null;

    if (!downloadOk) {
      callback(chart, -1);
      return;
    }

    if(_cancelDownloadAndDelete) {
      callback(chart, -1);
      await _deleteZipFile(localFile);
      return;
    }

    await _beginDbReplace();

    if(_cancelDownloadAndDelete) {
      callback(chart, -1);
      await _deleteZipFile(localFile);
      return;
    }

    final unzipReceive = ReceivePort();
    final unzipCompleter = Completer<bool>();
    late final StreamSubscription<dynamic> unzipSub;
    unzipSub = unzipReceive.listen((dynamic message) {
      if (message is! Map) {
        return;
      }
      final map = message.cast<String, Object?>();
      if (map.containsKey(_kSetupCancel)) {
        _chartUnzipCancelSendPort = map[_kSetupCancel] as SendPort;
        return;
      }
      if (map.containsKey(_kProgress)) {
        final double progress = map[_kProgress]! as double;
        if (progress - lastProgress >= 0.1) {
          callback(chart, (progress * 100).toInt());
          lastProgress = progress;
        }
        return;
      }
      if (map.containsKey(_kOk)) {
        unzipCompleter.complete(map[_kOk]! as bool);
      }
    });

    await Isolate.spawn(
      _chartUnzipIsolateEntry,
      <String, Object?>{
        _kReply: unzipReceive.sendPort,
        _kDataDir: dataDir,
        _kChartFilename: chart.filename,
      },
    );

    final bool unzipOk = await unzipCompleter.future;
    await unzipSub.cancel();
    unzipReceive.close();
    _chartUnzipCancelSendPort = null;

    if (!unzipOk) {
      callback(chart, -1);
      await _deleteZipFile(localFile);
      return;
    }

    if(_cancelDownloadAndDelete) {
      callback(chart, -1);
      await _deleteZipFile(localFile);
      return;
    }

    try {
      await Storage().checkDataExpiry();
      await Storage().checkChartsExist();
      await _endDbReplace();
      callback(chart, 100); // done
    } catch (e) {
      callback(chart, -1);
    }

    // clean up
    await _deleteZipFile(localFile);

  }
}
