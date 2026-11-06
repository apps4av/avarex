import 'dart:math';

import 'package:avaremp/visual_traffic/dot_detector.dart';

/// One target followed from frame to frame.
///
/// Positions are kept in scene coordinates: image position plus the total
/// slide of the scene since the start. A distant object that does not move on
/// its own stays at the same scene position however the camera turns.
class Track {
  Track({
    required this.id,
    required this.sceneX,
    required this.sceneY,
    required this.imageX,
    required this.imageY,
    required this.birthSlideX,
    required this.birthSlideY,
    required this.birthFrame,
  })  : birthImageX = imageX,
        birthImageY = imageY;

  final int id;
  final int birthFrame;

  double sceneX;
  double sceneY;

  /// Scene velocity in analysis pixels per frame. Zero for something fixed in
  /// the world or far away on a constant bearing.
  double velocityX = 0;
  double velocityY = 0;

  /// Latest position in the picture.
  double imageX;
  double imageY;
  final double birthImageX;
  final double birthImageY;
  final double birthSlideX;
  final double birthSlideY;

  double width = 1;
  double height = 1;
  double contrast = 0;
  bool below = false;

  int age = 0;
  int hits = 0;

  /// Frames in a row with no matching spot.
  int misses = 0;

  /// One bit per recent frame, newest in bit 0. 1 means a spot matched.
  int history = 0;

  /// A speck on the windshield: fixed in the picture while the scene slid.
  bool glass = false;

  // Model results.
  bool airplane = false;
  double airplaneScore = 0;
  bool bird = false;
  int birdChecks = 0;

  /// Highest airplane score the model gave this target on any look, even a
  /// score too low to count. For the Why window.
  double bestAirplaneScore = 0;

  /// Bird score from the look that made it a bird.
  double birdScoreSeen = 0;
  int checks = 0;
  int airplaneMisses = 0;
  int lastCheckFrame = -1000;

  int get windowHits => _popcount(history & 0xFFF);

  double get speed => sqrt(velocityX * velocityX + velocityY * velocityY);

  /// Moving on its own against the scene, steadily enough to be real.
  bool get moving => age >= 5 && speed > 0.25;

  /// Seen consistently enough to be worth showing or classifying.
  bool get persistent {
    if (glass || bird) {
      return false;
    }
    if (moving && windowHits >= 5) {
      return true;
    }
    return age >= 12 && windowHits >= 9;
  }

  double get consistency => (windowHits / 12).clamp(0.0, 1.0);

  static int _popcount(int v) {
    int n = 0;
    int x = v;
    while (x != 0) {
      n += x & 1;
      x >>= 1;
    }
    return n;
  }
}

/// Follows spots across frames and decides which ones keep showing up.
class Tracker {
  Tracker({
    this.gate = 4,
    this.maxMisses = 6,
    this.maxTracks = 60,
  });

  /// Largest distance, in analysis pixels, between where a track is expected
  /// and a spot that can be matched to it.
  final double gate;
  final int maxMisses;
  final int maxTracks;

  final List<Track> tracks = [];
  int _nextId = 1;
  int _frame = 0;

  int get frame => _frame;

  /// Adds one frame's [spots]. [slideX] and [slideY] are the total slide of
  /// the scene since tracking began (the sum of every frame's global motion).
  void update(List<DotCandidate> spots, double slideX, double slideY) {
    _frame++;
    final List<_Pair> pairs = [];
    for (int t = 0; t < tracks.length; t++) {
      final Track track = tracks[t];
      final double px = track.sceneX + track.velocityX;
      final double py = track.sceneY + track.velocityY;
      // Allow a little more slack for a track that has been missing.
      final double g = gate + track.misses * 0.75;
      for (int s = 0; s < spots.length; s++) {
        final double sx = spots[s].x + slideX;
        final double sy = spots[s].y + slideY;
        final double d = sqrt((sx - px) * (sx - px) + (sy - py) * (sy - py));
        if (d <= g) {
          pairs.add(_Pair(t, s, d));
        }
      }
    }
    pairs.sort((_Pair a, _Pair b) => a.distance.compareTo(b.distance));
    final Set<int> usedTracks = {};
    final Set<int> usedSpots = {};
    for (final _Pair pair in pairs) {
      if (usedTracks.contains(pair.track) || usedSpots.contains(pair.spot)) {
        continue;
      }
      usedTracks.add(pair.track);
      usedSpots.add(pair.spot);
      _apply(tracks[pair.track], spots[pair.spot], slideX, slideY);
    }

    for (int t = 0; t < tracks.length; t++) {
      final Track track = tracks[t];
      track.age++;
      if (usedTracks.contains(t)) {
        continue;
      }
      track.misses++;
      track.history = (track.history << 1) & 0xFFFF;
      // Coast on the last velocity so a brief miss does not lose it.
      track.sceneX += track.velocityX;
      track.sceneY += track.velocityY;
      track.imageX = track.sceneX - slideX;
      track.imageY = track.sceneY - slideY;
    }

    tracks.removeWhere((Track track) {
      if (track.misses > maxMisses) {
        return true;
      }
      // A track that has hardly ever matched is noise.
      return track.age >= 10 && track.windowHits < 3;
    });

    for (int s = 0; s < spots.length && tracks.length < maxTracks; s++) {
      if (usedSpots.contains(s)) {
        continue;
      }
      final DotCandidate spot = spots[s];
      final Track track = Track(
        id: _nextId++,
        sceneX: spot.x + slideX,
        sceneY: spot.y + slideY,
        imageX: spot.x,
        imageY: spot.y,
        birthSlideX: slideX,
        birthSlideY: slideY,
        birthFrame: _frame,
      );
      track.width = spot.width.toDouble();
      track.height = spot.height.toDouble();
      track.contrast = spot.contrast;
      track.below = spot.below;
      track.hits = 1;
      track.history = 1;
      track.age = 1;
      tracks.add(track);
    }

    for (final Track track in tracks) {
      _checkGlass(track, slideX, slideY);
    }
  }

  void _apply(Track track, DotCandidate spot, double slideX, double slideY) {
    final double sx = spot.x + slideX;
    final double sy = spot.y + slideY;
    // Velocity is smoothed. Position follows the spot more closely.
    final double vx = sx - track.sceneX;
    final double vy = sy - track.sceneY;
    track.velocityX = track.velocityX * 0.7 + vx * 0.3;
    track.velocityY = track.velocityY * 0.7 + vy * 0.3;
    track.sceneX = sx;
    track.sceneY = sy;
    track.imageX = spot.x;
    track.imageY = spot.y;
    track.width = track.width * 0.6 + spot.width * 0.4;
    track.height = track.height * 0.6 + spot.height * 0.4;
    track.contrast = track.contrast * 0.6 + spot.contrast * 0.4;
    track.below = spot.below;
    track.hits++;
    track.misses = 0;
    track.history = ((track.history << 1) | 1) & 0xFFFF;
  }

  /// A speck on the windshield stays put in the picture while the scene
  /// slides past it. Real objects slide with the scene or move on their own.
  void _checkGlass(Track track, double slideX, double slideY) {
    if (track.glass) {
      return;
    }
    final double slid = sqrt(pow(slideX - track.birthSlideX, 2) +
        pow(slideY - track.birthSlideY, 2));
    final double moved = sqrt(pow(track.imageX - track.birthImageX, 2) +
        pow(track.imageY - track.birthImageY, 2));
    if (slid >= 10 && moved < 2.5 && track.hits >= 4) {
      track.glass = true;
    }
  }
}

class _Pair {
  const _Pair(this.track, this.spot, this.distance);
  final int track;
  final int spot;
  final double distance;
}
