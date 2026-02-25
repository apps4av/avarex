import 'dart:convert';
import 'package:avaremp/utils/toast.dart';
import 'package:universal_io/io.dart';

import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:scribble/scribble.dart';
import 'package:toastification/toastification.dart';
import 'package:value_notifier_tools/value_notifier_tools.dart';

class WritingScreen extends StatefulWidget {
  const WritingScreen({super.key});
  @override
  State<StatefulWidget> createState() => WritingScreenState();
}

class WritingScreenState extends State<WritingScreen> {
  late ScribbleNotifier notifier;
  final ValueNotifier<bool> _showNumberPad = ValueNotifier(false);
  final ValueNotifier<String> _enteredNumbers = ValueNotifier("");

  @override
  void initState() {
    super.initState();
    notifier = ScribbleNotifier();
  }

  @override
  void dispose() {
    UserDatabaseHelper.db.saveSketch("Default", jsonEncode(notifier.currentSketch.toJson()));
    // remove data entered via number pad
    _showNumberPad.dispose();
    _enteredNumbers.dispose();
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
                  // overlay for displaying numbers entered via number pad
                  ValueListenableBuilder<String>(
                    valueListenable: _enteredNumbers,
                    builder: (context, text, child) {
                      if (text.isEmpty) return const SizedBox();
                      final lines = text.split('\n');
                      return Positioned(
                        top: 20,
                        left: 0,
                        right: 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: lines.asMap().entries.map((entry) {
                            final index = entry.key;
                            final line = entry.value;
                            return ValueListenableBuilder(
                              valueListenable: notifier,
                              builder: (context, state, child) {
                                Color color = Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white;
                                return IgnorePointer(
                                  ignoring: state is! Erasing,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      // Remove specific line if eraser is active
                                      final currentLines = _enteredNumbers.value.split('\n');
                                      if (index < currentLines.length) {
                                        currentLines.removeAt(index);
                                        _enteredNumbers.value = currentLines.join('\n');
                                      }
                                    },
                                    child: Center(
                                      child: Text(
                                        line.isEmpty ? " " : line,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 50,
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ])
                ),
                // number pad UI section
                ValueListenableBuilder<bool>(
                  valueListenable: _showNumberPad,
                  builder: (context, show, child) {
                    if (!show) return const SizedBox();
                    return _buildNumberPad(context);
                  },
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
        onPressed: () {
          notifier.clear();
          // clear number pad input when clearing the sketch
          _enteredNumbers.value = "";
        },
      ),
      IconButton(
          icon: const Icon(Icons.save),
          tooltip: "Save to Documents",
          onPressed: () {
            notifier.renderImage().then((image) {
              String now = DateTime.now().toIso8601String();
              File(PathUtils.getFilePath(Storage().dataDir, 'notes_$now.jpg')).writeAsBytes(image.buffer.asUint8List());
              if(context.mounted) {
                Toast.showToast(context, "Saved to Documents as notes_$now.jpg", null, 3);
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
        _buildNumberPadButton(context),
        _buildColorButton(context, color: Theme.of(context).brightness == Brightness.light ? Colors.black: Colors.white),
        _buildColorButton(context, color: Colors.red),
        _buildColorButton(context, color: Colors.green),
        _buildEraserButton(context),
      ],
    );
  }

  // toggle button for number pad in toolbar
  Widget _buildNumberPadButton(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _showNumberPad,
      builder: (context, show, child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ColorButton(
          color: Colors.transparent,
          outlineColor: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
          isActive: show,
          onPressed: () => _showNumberPad.value = !show,
          child: Text(
            "123",
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // layout of the number pad
  Widget _buildNumberPad(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light ? Colors.grey[200] : Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row in [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            [".", "0", "⌫"],
            ["ENTER"]
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row.map((e) => _buildKey(e)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // individual keys for the number pad
  Widget _buildKey(String label) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(
              color: Theme.of(context).brightness == Brightness.light ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () {
            if (label == "⌫") {
              if (_enteredNumbers.value.isNotEmpty) {
                _enteredNumbers.value = _enteredNumbers.value.substring(0, _enteredNumbers.value.length - 1);
              }
            } else if (label == "ENTER") {
              _enteredNumbers.value += "\n";
            } else {
              _enteredNumbers.value += label;
            }
          },
          child: label == "ENTER"
              ? const Icon(Icons.keyboard_return)
              : Text(
                  label,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
        ),
      ),
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

  final Widget? child;

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