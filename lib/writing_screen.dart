import 'dart:convert';
import 'dart:ui' as ui;
import 'package:avaremp/utils/toast.dart';
import 'package:universal_io/io.dart';

import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:scribble/scribble.dart';
import 'package:toastification/toastification.dart';
import 'package:value_notifier_tools/value_notifier_tools.dart';

enum BackgroundSheet {
  none('None'),
  ifrCraft('IFR CRAFT'),
  vfrAtis('VFR ATIS');

  final String label;
  const BackgroundSheet(this.label);
}

class WritingScreen extends StatefulWidget {
  const WritingScreen({super.key});
  @override
  State<StatefulWidget> createState() => WritingScreenState();
}

class WritingScreenState extends State<WritingScreen> {
  late ScribbleNotifier notifier;
  BackgroundSheet _selectedSheet = BackgroundSheet.none;
  final GlobalKey _canvasKey = GlobalKey();

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
                  RepaintBoundary(
                    key: _canvasKey,
                    child: Container(
                      color: Theme.of(context).brightness == Brightness.light ? Colors.white: Colors.black,
                      child: CustomPaint(
                        painter: _BackgroundSheetPainter(
                          sheet: _selectedSheet,
                          isDark: Theme.of(context).brightness == Brightness.dark,
                        ),
                        child: Scribble(notifier: notifier, drawPen: false, drawEraser: false),
                      ),
                    ),
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
      PopupMenuButton<BackgroundSheet>(
        icon: const Icon(Icons.note_alt_outlined),
        tooltip: "Background Sheet",
        onSelected: (BackgroundSheet sheet) {
          setState(() {
            _selectedSheet = sheet;
          });
        },
        itemBuilder: (context) => BackgroundSheet.values.map((sheet) {
          return PopupMenuItem<BackgroundSheet>(
            value: sheet,
            child: Row(
              children: [
                if (_selectedSheet == sheet)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(sheet.label),
              ],
            ),
          );
        }).toList(),
      ),
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
          onPressed: () async {
            try {
              final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
              if (boundary == null) return;
              
              final image = await boundary.toImage(pixelRatio: 2.0);
              final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
              if (byteData == null) return;
              
              String now = DateTime.now().toIso8601String();
              await File(PathUtils.getFilePath(Storage().dataDir, 'notes_$now.png')).writeAsBytes(byteData.buffer.asUint8List());
              if(context.mounted) {
                Toast.showToast(context, "Saved to Documents as notes_$now.png", null, 3);
              }
            } catch (e) {
              if(context.mounted) {
                Toast.showToast(context, "Failed to save image", null, 3);
              }
            }
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

class _BackgroundSheetPainter extends CustomPainter {
  final BackgroundSheet sheet;
  final bool isDark;

  _BackgroundSheetPainter({required this.sheet, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (sheet == BackgroundSheet.none) return;

    final lineColor = isDark ? Colors.grey.shade600 : Colors.grey.shade400;
    final textColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final textStyle = TextStyle(
      color: textColor,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );

    if (sheet == BackgroundSheet.ifrCraft) {
      _drawIfrCraftSheet(canvas, size, linePaint, textStyle);
    } else if (sheet == BackgroundSheet.vfrAtis) {
      _drawVfrAtisSheet(canvas, size, linePaint, textStyle);
    }
  }

  void _drawIfrCraftSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 8;
    final double labelWidth = 120;

    final labels = [
      'C - Clearance Limit',
      'R - Route',
      'A - Altitude',
      'F - Frequency',
      'T - Transponder',
      'Remarks',
      'Readback',
      'Notes',
    ];

    for (int i = 0; i < labels.length; i++) {
      final y = padding + i * rowHeight;
      
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        linePaint,
      );

      final textSpan = TextSpan(text: labels[i], style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(padding + 4, y + 4));

      canvas.drawLine(
        Offset(padding + labelWidth, y),
        Offset(padding + labelWidth, y + rowHeight),
        linePaint,
      );
    }

    canvas.drawLine(
      Offset(padding, padding + labels.length * rowHeight),
      Offset(size.width - padding, padding + labels.length * rowHeight),
      linePaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(padding, padding, size.width - padding * 2, labels.length * rowHeight),
      linePaint,
    );
  }

  void _drawVfrAtisSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 12;
    final double labelWidth = 140;

    final labels = [
      'Airport',
      'ATIS Letter',
      'Time (Z)',
      'Wind',
      'Visibility',
      'Sky Condition',
      'Temperature',
      'Dewpoint',
      'Altimeter',
      'Runway(s) in Use',
      'NOTAMs',
      'Remarks',
    ];

    for (int i = 0; i < labels.length; i++) {
      final y = padding + i * rowHeight;
      
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        linePaint,
      );

      final textSpan = TextSpan(text: labels[i], style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(padding + 4, y + 4));

      canvas.drawLine(
        Offset(padding + labelWidth, y),
        Offset(padding + labelWidth, y + rowHeight),
        linePaint,
      );
    }

    canvas.drawLine(
      Offset(padding, padding + labels.length * rowHeight),
      Offset(size.width - padding, padding + labels.length * rowHeight),
      linePaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(padding, padding, size.width - padding * 2, labels.length * rowHeight),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BackgroundSheetPainter oldDelegate) {
    return oldDelegate.sheet != sheet || oldDelegate.isDark != isDark;
  }
}