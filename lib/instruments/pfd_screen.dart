import 'package:avaremp/instruments/pfd_painter.dart';
import 'package:flutter/material.dart';

/// Menu entry for the same [PfdView] used by the map PFD layer.
class PfdScreen extends StatelessWidget {
  const PfdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PFD')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Same width/height ratio as the map inset, grown to this screen.
          double height = constraints.maxHeight;
          double width = height * 0.7;
          if (width > constraints.maxWidth) {
            width = constraints.maxWidth;
            height = width / 0.7;
          }
          return Center(
            child: PfdView(width: width, height: height),
          );
        },
      ),
    );
  }
}
