import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:avaremp/utils/app_log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart';

/// Captures raw ADS-B/GDL90 bytes to a daily file named by capture date.
///
/// Each received chunk is appended as:
/// `<ms since epoch>\t<hex bytes>\n`
class AdsbCapture {
  static final AdsbCapture _instance = AdsbCapture._internal();
  factory AdsbCapture() => _instance;
  AdsbCapture._internal();

  IOSink? _sink;
  String? _activeDate; // yyyy-MM-dd (local)
  String? _baseDir;
  bool _rotating = false;
  final List<_PendingLine> _pending = [];
  static const int _maxPendingLines = 5000;
  int _lastFlushMs = 0;
  bool _flushScheduled = false;
  int _lastStatusLogMs = 0;
  int _bytesSeenSinceLog = 0;
  int _lastNoBaseDirLogMs = 0;

  void configure({required String baseDir}) {
    _baseDir = baseDir;
  }

  void capture(Uint8List data) {
    if (kIsWeb) {
      return;
    }
    final baseDir = _baseDir;
    if (baseDir == null || baseDir.isEmpty) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastNoBaseDirLogMs > 10 * 1000) {
        _lastNoBaseDirLogMs = nowMs;
        AppLog.logMessage("ADS-B capture: baseDir not set (dropping)");
      }
      return;
    }

    final now = DateTime.now();
    _maybeLogStatus(now, data.length);
    final date = _formatDate(now);
    if (_sink == null || _activeDate != date) {
      _enqueue(now, data);
      if (!_rotating) {
        _rotating = true;
        // Fire-and-forget; keep receiver hot.
        unawaited(() async {
          try {
            await _rotateTo(date);
            _flushPending();
          } finally {
            _rotating = false;
          }
        }());
      }
      return;
    }

    _writeLine(now, data);
  }

  Future<void> stop() async {
    await _closeSink();
  }

  Future<void> _rotateTo(String date) async {
    await _closeSink();

    final baseDir = _baseDir;
    if (baseDir == null || baseDir.isEmpty) {
      return;
    }

    final folder = path.join(baseDir, 'adsb_captures');
    final dir = Directory(folder);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final filePath = path.join(folder, '$date.adsb');
    final file = File(filePath);
    _sink = file.openWrite(mode: FileMode.append, encoding: utf8);
    _activeDate = date;
    AppLog.logMessage("ADS-B capture: writing to $filePath");
  }

  Future<void> _closeSink() async {
    final sink = _sink;
    _sink = null;
    _activeDate = null;
    if (sink != null) {
      try {
        await sink.flush();
        await sink.close();
      } catch (e) {
        AppLog.logMessage("ADS-B capture close error: $e");
      }
    }
  }

  void _writeLine(DateTime timestamp, Uint8List data) {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    try {
      sink.writeln('${timestamp.millisecondsSinceEpoch}\t${_toHex(data)}');
      _scheduleFlush();
    } catch (e) {
      AppLog.logMessage("ADS-B capture write error: $e");
    }
  }

  void _enqueue(DateTime timestamp, Uint8List data) {
    if (_pending.length >= _maxPendingLines) {
      // Prevent unbounded memory use if filesystem is unavailable.
      _pending.removeAt(0);
    }
    _pending.add(_PendingLine(timestamp, Uint8List.fromList(data)));
  }

  void _flushPending() {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    if (_pending.isEmpty) {
      return;
    }
    final pending = List<_PendingLine>.from(_pending);
    _pending.clear();
    for (final p in pending) {
      _writeLine(p.timestamp, p.data);
    }
  }

  void _scheduleFlush() {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Avoid flushing every line; still make output visible quickly.
    if (nowMs - _lastFlushMs >= 1000) {
      _lastFlushMs = nowMs;
      unawaited(sink.flush());
      return;
    }
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    unawaited(() async {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        final s = _sink;
        if (s != null) {
          _lastFlushMs = DateTime.now().millisecondsSinceEpoch;
          await s.flush();
        }
      } catch (e) {
        AppLog.logMessage("ADS-B capture flush error: $e");
      } finally {
        _flushScheduled = false;
      }
    }());
  }

  void _maybeLogStatus(DateTime now, int len) {
    final nowMs = now.millisecondsSinceEpoch;
    _bytesSeenSinceLog += len;
    if (nowMs - _lastStatusLogMs < 15 * 1000) {
      return;
    }
    _lastStatusLogMs = nowMs;
    final date = _formatDate(now);
    final baseDir = _baseDir ?? "(null)";
    AppLog.logMessage(
      "ADS-B capture: rx=${_bytesSeenSinceLog} bytes in 15s date=$date baseDir=$baseDir",
    );
    _bytesSeenSinceLog = 0;
  }

  static String _formatDate(DateTime d) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  static String _toHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

class _PendingLine {
  final DateTime timestamp;
  final Uint8List data;
  _PendingLine(this.timestamp, this.data);
}

