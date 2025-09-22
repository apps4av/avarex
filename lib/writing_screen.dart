import 'dart:convert';
import 'dart:io';

import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:scribble/scribble.dart';
import 'package:toastification/toastification.dart';
import 'package:value_notifier_tools/value_notifier_tools.dart';

import 'map_screen.dart';

class WritingScreen extends StatefulWidget {
  const WritingScreen({super.key});
  @override
  State<StatefulWidget> createState() => WritingScreenState();
}

class WritingScreenState extends State<WritingScreen> {
  late ScribbleNotifier notifier;

  @override
  void initState() {
    super.initState();
    notifier = ScribbleNotifier();
  }

  @override
  void dispose() {
    UserDatabaseHelper.db.saveSketch("Default", jsonEncode(notifier.currentSketch.toJson()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    notifier.setStrokeWidth(2);
    notifier.setColor(Theme.of(context).brightness == Brightness.light ? Colors.black: Colors.white);
    return FutureBuilder(
      future: UserDatabaseHelper.db.getSketch("Default"),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          if(snapshot.data!.isNotEmpty) {
            notifier.setSketch(sketch: Sketch.fromJson(jsonDecode(snapshot.data!)));
          }
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text("Notes"),
            actions: _buildActions(context),
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(
              children: [
                Expanded(child:
                Stack(children: [
                  Container(color: Theme.of(context).brightness == Brightness.light ? Colors.white: Colors.black, child:
                  Scribble(notifier: notifier, drawPen: false, drawEraser: false)
                  ),
                ])
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: _buildColorToolbar(context),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      ValueListenableBuilder(
        valueListenable: notifier,
        builder: (context, value, child) => IconButton(
          icon: child as Icon,
          tooltip: "Undo",
          onPressed: notifier.canUndo ? notifier.undo : null,
        ),
        child: const Icon(Icons.undo),
      ),
      ValueListenableBuilder(
        valueListenable: notifier,
        builder: (context, value, child) => IconButton(
          icon: child as Icon,
          tooltip: "Redo",
          onPressed: notifier.canRedo ? notifier.redo : null,
        ),
        child: const Icon(Icons.redo),
      ),
      IconButton(
        icon: Icon(MdiIcons.eraser),
        tooltip: "Clear",
        onPressed: notifier.clear,
      ),
      IconButton(
          icon: const Icon(Icons.save),
          tooltip: "Save to Documents",
          onPressed: () {
            notifier.renderImage().then((image) {
              String now = DateTime.now().toIso8601String();
              File(PathUtils.getFilePath(Storage().dataDir, 'notes_$now.jpg')).writeAsBytes(image.buffer.asUint8List());
              if(context.mounted) {
                MapScreenState.showToast(context, "Saved to Documents as notes_$now.jpg", null, 3);
              }
            });
          }),
    ];
  }

  Widget _buildColorToolbar(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _buildColorButton(context, color: Theme.of(context).brightness == Brightness.light ? Colors.black: Colors.white),
        _buildColorButton(context, color: Colors.red),
        _buildColorButton(context, color: Colors.green),
        _buildEraserButton(context),
      ],
    );
  }

  Widget _buildEraserButton(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: notifier.select((value) => value is Erasing),
      builder: (context, value, child) => ColorButton(
        color: Colors.transparent,
        outlineColor: Theme.of(context).brightness == Brightness.light ? Colors.black: Colors.white,
        isActive: value,
        onPressed: ()  {notifier.setEraser(); notifier.setStrokeWidth(10);},
        child: const Icon(Icons.cleaning_services),
      ),
    );
  }

  Widget _buildColorButton(
      BuildContext context, {
        required Color color,
      }) {
    return ValueListenableBuilder(
      valueListenable: notifier.select(
              (value) => value is Drawing && value.selectedColor == color.intValue),
      builder: (context, value, child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ColorButton(
          color: color,
          isActive: value,
          onPressed: () {notifier.setColor(color); notifier.setStrokeWidth(2);},
        ),
      ),
    );
  }
}

class ColorButton extends StatelessWidget {
  const ColorButton({
    required this.color,
    required this.isActive,
    required this.onPressed,
    this.outlineColor,
    this.child,
    super.key,
  });

  final Color color;

  final Color? outlineColor;

  final bool isActive;

  final VoidCallback onPressed;

  final Icon? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kThemeAnimationDuration,
      decoration: ShapeDecoration(
        shape: CircleBorder(
          side: BorderSide(
            color: switch (isActive) {
              true => outlineColor ?? color,
              false => Colors.transparent,
            },
            width: 2,
          ),
        ),
      ),
      child: IconButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape: const CircleBorder(),
          side: isActive
              ? BorderSide(color: Theme.of(context).brightness == Brightness.light ? Colors.white: Colors.black, width: 2)
              : const BorderSide(color: Colors.transparent),
        ),
        onPressed: onPressed,
        icon: child ?? const SizedBox(),
      ),
    );
  }
}