import 'dart:typed_data';

import 'package:avaremp/instruments/synthetic_vision_hud.dart';
import 'package:flutter/material.dart';

/// Draws synthetic-vision terrain as a triangle mesh.
///
/// This uses a vertex pipeline similar to OpenGL-style rendering:
/// quads are converted to triangles and submitted in one draw call.
class OpenGlHudRenderer {
  static void drawTerrainMesh({
    required Canvas canvas,
    required SyntheticVisionFrame frame,
    required double Function(double) xTransform,
    required double Function(double) yTransform,
    required double pitchDegreeScale,
  }) {
    if (!frame.hasTerrain || frame.quads.isEmpty) {
      return;
    }

    // Two triangles per quad, three vertices per triangle.
    final int vertexCount = frame.quads.length * 6;
    final Float32List positions = Float32List(vertexCount * 2);
    final Int32List colors = Int32List(vertexCount);

    int positionIndex = 0;
    int colorIndex = 0;

    for (final SyntheticVisionQuad quad in frame.quads) {
      final double x1 = xTransform(quad.leftX);
      final double y1 = yTransform(quad.nearLeftAngleDeg * pitchDegreeScale);
      final double x2 = xTransform(quad.rightX);
      final double y2 = yTransform(quad.nearRightAngleDeg * pitchDegreeScale);
      final double x3 = xTransform(quad.rightX);
      final double y3 = yTransform(quad.farRightAngleDeg * pitchDegreeScale);
      final double x4 = xTransform(quad.leftX);
      final double y4 = yTransform(quad.farLeftAngleDeg * pitchDegreeScale);

      final int argb =
          (quad.color.alpha << 24) |
          (quad.color.red << 16) |
          (quad.color.green << 8) |
          quad.color.blue;

      // Triangle 1: p1, p2, p3
      positions[positionIndex++] = x1;
      positions[positionIndex++] = y1;
      colors[colorIndex++] = argb;

      positions[positionIndex++] = x2;
      positions[positionIndex++] = y2;
      colors[colorIndex++] = argb;

      positions[positionIndex++] = x3;
      positions[positionIndex++] = y3;
      colors[colorIndex++] = argb;

      // Triangle 2: p1, p3, p4
      positions[positionIndex++] = x1;
      positions[positionIndex++] = y1;
      colors[colorIndex++] = argb;

      positions[positionIndex++] = x3;
      positions[positionIndex++] = y3;
      colors[colorIndex++] = argb;

      positions[positionIndex++] = x4;
      positions[positionIndex++] = y4;
      colors[colorIndex++] = argb;
    }

    final Vertices vertices = Vertices.raw(
      VertexMode.triangles,
      positions,
      colors: colors,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint()..isAntiAlias = true);
  }
}
