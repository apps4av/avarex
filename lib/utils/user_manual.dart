import 'dart:typed_data';

import 'package:avaremp/constants.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/io.dart';
import 'package:yaml/yaml.dart';

/// The user manual that ships inside the app.
class UserManual {
  static const String asset = 'assets/docs/USER_MANUAL.pdf';

  /// Copies [asset] into the documents folder as `User Manual X.Y.Z.pdf`.
  /// Called when Help is opened. An older `USER_MANUAL.pdf` or a previous
  /// version's file is removed then, so Documents shows this release's manual.
  static Future<String?> install() async {
    if (kIsWeb || !Constants.shouldShowPdf) {
      return null;
    }
    final String version = await _versionName();
    final String name = fileNameForVersion(version);
    final Directory dir = Directory(Storage().dataDir);
    final File file = File(PathUtils.getFilePath(dir.path, name));
    final ByteData data = await rootBundle.load(asset);
    final Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await file.writeAsBytes(bytes, flush: true);
    await _removeOlder(dir, name);
    return file.path;
  }

  static String fileNameForVersion(String version) => 'User Manual $version.pdf';

  /// True for a manual this app wrote for another release.
  static bool isOlderManual(String name, String current) {
    if (name == current) {
      return false;
    }
    if (name == 'USER_MANUAL.pdf' || name == 'USER_MANUAL.pdf.stamp') {
      return true;
    }
    return RegExp(r'^User Manual \d+\.\d+\.\d+\.pdf$').hasMatch(name);
  }

  static Future<String> _versionName() async {
    final String raw = await rootBundle.loadString('pubspec.yaml');
    final dynamic doc = loadYaml(raw);
    final String name = doc['version'].toString().split('+').first.trim();
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(name)) {
      throw FormatException('Unexpected app version: $name');
    }
    return name;
  }

  static Future<void> _removeOlder(Directory dir, String current) async {
    await for (final FileSystemEntity entity in dir.list()) {
      if (entity is! File) {
        continue;
      }
      if (isOlderManual(PathUtils.filename(entity.path), current)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }
}
