import 'package:flutter/material.dart';

import 'ofm_constants.dart';

class OfmAttribution extends StatelessWidget {
  final double opacity;

  const OfmAttribution({super.key, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Container(
            margin: const EdgeInsets.only(left: 8, bottom: 84),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(150),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              OfmConstants.attribution,
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }
}
