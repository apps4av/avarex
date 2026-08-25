import 'package:flutter_map/flutter_map.dart';

class MapControllerGuard {
  MapControllerGuard._();

  static MapCamera? cameraIfReady(MapController controller, bool ready) {
    if (!ready) return null;
    return controller.camera;
  }
}
