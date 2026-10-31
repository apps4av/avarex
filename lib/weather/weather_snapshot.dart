import 'package:flutter/foundation.dart';

/// A weather layer for the 3D Weather screen that is built on demand and kept as a
/// snapshot: it records when it was built and stops being shown after [life].
abstract class SnapshotCache extends ChangeNotifier {
  /// How long a build stays on screen before it must be built again.
  Duration get life;

  /// When the data was last fetched, or null with no build.
  DateTime? get builtAt;

  bool get loading;

  /// Why there is no picture, or null.
  String? get message;

  /// What the layer's button says while it loads, such as `Building 2/5`. Null when idle.
  String? get progress;

  /// Whether there is something to draw.
  bool get hasPicture;

  /// Loads or reloads the layer around [lat]/[lon]. Calls made while a load is
  /// running join that load.
  Future<void> refresh(double lat, double lon, {bool force = false});

  /// Whether the layer no longer covers [lat]/[lon], so it should be built again.
  bool needsRegrid(double lat, double lon);

  /// True once the build is older than [life].
  bool get expired {
    final built = builtAt;
    return built != null && DateTime.now().difference(built) > life;
  }

  /// Time left before the build expires, never negative. Null with no build.
  Duration? get lifeLeft {
    final built = builtAt;
    if (built == null) {
      return null;
    }
    final left = life - DateTime.now().difference(built);
    return left.isNegative ? Duration.zero : left;
  }
}
