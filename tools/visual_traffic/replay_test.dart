// Runs the Visual Traffic detector over a folder of recorded frames, so the
// thresholds can be tuned on real footage without flying.
//
// 1. Turn a cockpit video into upright frames, about 10 a second:
//
//      mkdir frames
//      ffmpeg -i flight.mp4 -vf fps=10 frames/%05d.png
//
// 2. Run the detector over them (from the project folder):
//
//      flutter test tools/visual_traffic/replay_test.dart \
//        --dart-define=VT_FRAMES=frames \
//        --dart-define=VT_OUT=replay_out \
//        --dart-define=VT_FOV=65 --dart-define=VT_SENS=1.0
//
//    VT_FRAMES  folder of .png or .jpg frames in name order (required)
//    VT_OUT     folder for copies with the boxes drawn on (optional)
//    VT_FOV     horizontal field of view in degrees, default 65
//    VT_SENS    sensitivity, 0.5 to 1.5, default 1.0
//    VT_FPS     frames per second of the recording, default 10
//    VT_MODEL   .tflite file, default the bundled one. Use "none" to run
//               without a model (yellow boxes only)
//
// It prints one line per frame and a summary. Frames with a red box are the
// ones to check first. Look for yellow boxes on clouds, glare, or the
// windshield, and for airplanes that never turned red, then change the
// sensitivity or the constants in lib/visual_traffic and run it again.
//
// This is a test file only so that `flutter test` supplies the LiteRT
// runtime. Without VT_FRAMES it does nothing, so a plain `flutter test` is
// not slowed down by it.

import 'dart:io';
import 'dart:typed_data';

import 'package:avaremp/visual_traffic/aircraft_detector.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/frame_analyzer.dart';
import 'package:avaremp/visual_traffic/luma_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const String _framesDir = String.fromEnvironment('VT_FRAMES');
const String _outDir = String.fromEnvironment('VT_OUT');
const String _modelPath =
    String.fromEnvironment('VT_MODEL', defaultValue: 'assets/models/yolox_nano.tflite');
const String _fovText = String.fromEnvironment('VT_FOV', defaultValue: '65');
const String _sensText = String.fromEnvironment('VT_SENS', defaultValue: '1.0');
const String _fpsText = String.fromEnvironment('VT_FPS', defaultValue: '10');

void main() {
  test('replay recorded frames', () {
    if (_framesDir.isEmpty) {
      markTestSkipped('Set --dart-define=VT_FRAMES=<folder> to run a replay.');
      return;
    }
    final Directory dir = Directory(_framesDir);
    expect(dir.existsSync(), isTrue, reason: 'No folder $_framesDir');
    final List<File> files = dir
        .listSync()
        .whereType<File>()
        .where((File f) {
          final String p = f.path.toLowerCase();
          return p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.jpeg');
        })
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: 'No .png or .jpg frames in $_framesDir');

    AircraftConfirmer? confirmer;
    if (_modelPath != 'none') {
      confirmer = TfliteAircraftConfirmer.create(File(_modelPath).readAsBytesSync());
      if (confirmer == null) {
        stdout.writeln('Model could not run here. Continuing without it.');
      }
    }
    final double fps = double.tryParse(_fpsText) ?? 10;
    final FrameAnalyzer analyzer = FrameAnalyzer(
      confirmer: confirmer,
      settings: AnalyzerSettings(
        fovH: double.tryParse(_fovText) ?? 65,
        sensitivity: double.tryParse(_sensText) ?? 1,
      ),
    );
    final Directory? out = _outDir.isEmpty ? null : Directory(_outDir);
    out?.createSync(recursive: true);

    int redFrames = 0, yellowFrames = 0, totalMs = 0;
    final Set<int> redIds = {}, yellowIds = {};
    stdout.writeln('frame,file,ms,red,yellow,boxes');
    for (int i = 0; i < files.length; i++) {
      final img.Image? picture = img.decodeImage(files[i].readAsBytesSync());
      if (picture == null) {
        stdout.writeln('$i,${files[i].path},skipped (not an image)');
        continue;
      }
      final Uint8List gray = Uint8List(picture.width * picture.height);
      for (int y = 0; y < picture.height; y++) {
        for (int x = 0; x < picture.width; x++) {
          gray[y * picture.width + x] =
              img.getLuminance(picture.getPixel(x, y)).round().clamp(0, 255);
        }
      }
      final AnalysisResult result = analyzer.process(
        LumaFrame.fromGray(GrayImage(picture.width, picture.height, gray)),
        timestampMs: (i * 1000 / fps).round(),
      );
      final List<DetectionBox> boxes = result.frame.boxes;
      final int red = boxes.where((DetectionBox b) => b.tier == DetectionTier.airplane).length;
      final int yellow = boxes.length - red;
      if (red > 0) redFrames++;
      if (yellow > 0) yellowFrames++;
      totalMs += result.milliseconds.round();
      for (final DetectionBox b in boxes) {
        (b.tier == DetectionTier.airplane ? redIds : yellowIds).add(b.id);
      }
      final String described = boxes
          .map((DetectionBox b) =>
              '${b.tier == DetectionTier.airplane ? "R" : "y"}${b.id}@'
              '${b.centerX.toStringAsFixed(3)},${b.centerY.toStringAsFixed(3)} '
              '${b.confidence.toStringAsFixed(2)}')
          .join(' | ');
      stdout.writeln('$i,${files[i].uri.pathSegments.last},'
          '${result.milliseconds.round()},$red,$yellow,$described');

      if (out != null) {
        for (final DetectionBox b in boxes) {
          final bool airplane = b.tier == DetectionTier.airplane;
          final int pad = 6;
          img.drawRect(
            picture,
            x1: (b.x * picture.width).round() - pad,
            y1: (b.y * picture.height).round() - pad,
            x2: ((b.x + b.w) * picture.width).round() + pad,
            y2: ((b.y + b.h) * picture.height).round() + pad,
            color: airplane ? img.ColorRgb8(255, 30, 30) : img.ColorRgb8(255, 214, 10),
            thickness: airplane ? 3 : 1,
          );
        }
        File('${out.path}/${files[i].uri.pathSegments.last.replaceAll(RegExp(r"\.\w+$"), "")}.png')
            .writeAsBytesSync(img.encodePng(picture));
      }
    }
    confirmer?.close();
    stdout.writeln('');
    stdout.writeln('Frames: ${files.length}');
    stdout.writeln('Frames with a red box: $redFrames (${redIds.length} separate targets)');
    stdout.writeln('Frames with a yellow box: $yellowFrames (${yellowIds.length} separate targets)');
    stdout.writeln('Average time per frame: ${(totalMs / files.length).toStringAsFixed(1)} ms');
  });
}
