import 'package:flutter/material.dart';

import 'openaip_constants.dart';

class OpenAipAttribution extends StatelessWidget {
  final double opacity;

  const OpenAipAttribution({super.key, required this.opacity});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          margin: const EdgeInsets.only(left: 8, bottom: 106),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(150),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            OpenAipConstants.attribution,
            style: TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
    ),
  );
}
