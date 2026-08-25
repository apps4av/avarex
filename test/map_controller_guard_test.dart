import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/utils/map_controller_guard.dart';

void main() {
  test('does not read camera before FlutterMap attaches the controller', () {
    final controller = MapController();

    expect(MapControllerGuard.cameraIfReady(controller, false), isNull);
  });
}
