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
  flightTimes('Cost'),
  vfrAtis('ATIS'),
  ifrCraft('CRAFT'),
  clearance('Clearance'),
  ground('Ground Taxi'),
  tower('Tower Takeoff'),
  departure('Departure'),
  approach('Approach'),
  towerArrival('Tower Landing'),
  groundLanding('Ground Landed');

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
  bool _showKeypad = false;
  String _typedText = '';
  bool _sketchLoaded = false;

  String _getSheetKey(BackgroundSheet sheet) => 'sketch_${sheet.name}';

  @override
  void initState() {
    super.initState();
    notifier = ScribbleNotifier();
    _loadSketchForSheet(_selectedSheet);
  }

  Future<void> _loadSketchForSheet(BackgroundSheet sheet) async {
    final data = await UserDatabaseHelper.db.getSketch(_getSheetKey(sheet));
    if (mounted) {
      if (data.isNotEmpty) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) {
            if (decoded.containsKey('sketch')) {
              notifier.setSketch(sketch: Sketch.fromJson(decoded['sketch']));
            } else if (decoded.containsKey('lines')) {
              notifier.setSketch(sketch: Sketch.fromJson(decoded));
            } else {
              notifier.clear();
            }
            _typedText = decoded['typedText'] ?? '';
          }
        } catch (e) {
          notifier.clear();
          _typedText = '';
        }
      } else {
        notifier.clear();
        _typedText = '';
      }
      setState(() {
        _sketchLoaded = true;
      });
    }
  }

  void _saveSketchForSheet(BackgroundSheet sheet) {
    final data = {
      'sketch': notifier.currentSketch.toJson(),
      'typedText': _typedText,
    };
    UserDatabaseHelper.db.saveSketch(_getSheetKey(sheet), jsonEncode(data));
  }

  Future<void> _switchSheet(BackgroundSheet newSheet) async {
    if (newSheet == _selectedSheet) return;
    
    _saveSketchForSheet(_selectedSheet);
    
    setState(() {
      _selectedSheet = newSheet;
    });
    
    await _loadSketchForSheet(newSheet);
  }

  @override
  void dispose() {
    _saveSketchForSheet(_selectedSheet);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    notifier.setStrokeWidth(2);
    notifier.setColor(Theme.of(context).brightness == Brightness.light ? Colors.black: Colors.white);
    
    if (!_sketchLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Notes"),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
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
                  child: Stack(
                    children: [
                      CustomPaint(
                        painter: _BackgroundSheetPainter(
                          sheet: _selectedSheet,
                          isDark: Theme.of(context).brightness == Brightness.dark,
                        ),
                        child: Scribble(notifier: notifier, drawPen: false, drawEraser: false),
                      ),
                      if (_typedText.isNotEmpty)
                        Positioned(
                          left: 20,
                          top: 20,
                          right: 20,
                          child: Text(
                            _typedText,
                            style: TextStyle(
                              fontSize: 24,
                              color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            softWrap: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_showKeypad)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _buildNumberKeypad(context),
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
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      PopupMenuButton<BackgroundSheet>(
        icon: const Icon(Icons.note_alt_outlined),
        tooltip: "Background Sheet",
        onSelected: (BackgroundSheet sheet) {
          _switchSheet(sheet);
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
              await PathUtils.ensureNotesFolderExists(Storage().dataDir);
              String notesFolder = PathUtils.getNotesFolder(Storage().dataDir);
              await File(PathUtils.getFilePath(notesFolder, 'notes_$now.png')).writeAsBytes(byteData.buffer.asUint8List());
              if(context.mounted) {
                Toast.showToast(context, "Saved to Documents/notes as notes_$now.png", null, 3);
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
        const SizedBox(width: 16),
        _buildKeypadButton(context),
      ],
    );
  }

  Widget _buildKeypadButton(BuildContext context) {
    return ColorButton(
      color: _showKeypad ? Colors.blue : Colors.transparent,
      outlineColor: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
      isActive: _showKeypad,
      onPressed: () {
        setState(() {
          _showKeypad = !_showKeypad;
        });
      },
      child: const Icon(Icons.dialpad),
    );
  }

  Widget _buildNumberKeypad(BuildContext context) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildKeypadKey('1'),
                _buildKeypadKey('2'),
                _buildKeypadKey('3'),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildKeypadKey('4'),
                _buildKeypadKey('5'),
                _buildKeypadKey('6'),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildKeypadKey('7'),
                _buildKeypadKey('8'),
                _buildKeypadKey('9'),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildKeypadKey('.'),
                _buildKeypadKey('0'),
                _buildKeypadKey('⌫', isBackspace: true),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildKeypadKey(' ', isSpace: true),
                _buildKeypadKey('↵', isNewline: true),
                _buildKeypadKey('C', isClear: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypadKey(String key, {bool isBackspace = false, bool isSpace = false, bool isClear = false, bool isNewline = false}) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: SizedBox(
        width: isSpace ? 40 : 40,
        height: 40,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
          ),
          onPressed: () {
            setState(() {
              if (isBackspace) {
                if (_typedText.isNotEmpty) {
                  _typedText = _typedText.substring(0, _typedText.length - 1);
                }
              } else if (isClear) {
                _typedText = '';
              } else if (isSpace) {
                _typedText += ' ';
              } else if (isNewline) {
                _typedText += '\n';
              } else {
                _typedText += key;
              }
            });
          },
          child: Text(isSpace ? '␣' : key, style: const TextStyle(fontSize: 18)),
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
    } else if (sheet == BackgroundSheet.flightTimes) {
      _drawFlightTimesSheet(canvas, size, linePaint, textStyle);
    } else if (sheet == BackgroundSheet.clearance) {
      _drawClearanceSheet(canvas, size, linePaint, textStyle);
    } else if (sheet == BackgroundSheet.ground) {
      _drawGroundSheet(canvas, size, linePaint, textStyle);
    } else if (sheet == BackgroundSheet.tower) {
      _drawTowerSheet(canvas, size, linePaint, textStyle);
    } else if (sheet == BackgroundSheet.departure) {
      _drawDepartureSheet(canvas, size, linePaint, textStyle);
    } else if (sheet == BackgroundSheet.approach) {
      _drawApproachSheet(canvas, size, linePaint, textStyle);
    } else if (sheet == BackgroundSheet.towerArrival) {
      _drawTowerArrivalSheet(canvas, size, linePaint, textStyle);
    } else if (sheet == BackgroundSheet.groundLanding) {
      _drawGroundLandingSheet(canvas, size, linePaint, textStyle);
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

  void _drawFlightTimesSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 6;
    final double labelWidth = 120;

    final labels = [
      'Start Hobbs',
      'End Hobbs',
      'Start Tach',
      'End Tach',
      'Fuel Added',
      'Oil Added',
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

  void _drawClearanceSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 5;
    final double scaleFactor = size.width / 400;
    final double fontSize = (11 * scaleFactor).clamp(9.0, 14.0);
    final smallStyle = textStyle.copyWith(fontSize: fontSize);
    double y = padding;

    void drawLabel(String text, double x, double labelY, {TextStyle? style}) {
      final textSpan = TextSpan(text: text, style: style ?? smallStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, labelY));
    }

    void drawLine(double x1, double x2, double lineY) {
      canvas.drawLine(Offset(x1, lineY), Offset(x2, lineY), linePaint);
    }

    double col1 = size.width * 0.15;
    double col2 = size.width * 0.45;
    double col3 = size.width * 0.75;

    // Row 1: facility, clearance N, type, a, tail
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('clearance, N', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 2: a, type/suffix, VFR to, destination
    drawLabel('a', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('VFR to', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 3: at, altitude, ft with info, ATIS
    drawLabel('at', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('ft with info', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 4: 4 fields for readback (dep hdg, alt, freq, squawk)
    double colW = (size.width - col1 - padding) / 4;
    drawLine(col1, col1 + colW - 5, y + rowHeight * 0.5);
    drawLine(col1 + colW, col1 + colW * 2 - 5, y + rowHeight * 0.5);
    drawLine(col1 + colW * 2, col1 + colW * 3 - 5, y + rowHeight * 0.5);
    drawLine(col1 + colW * 3, size.width - padding, y + rowHeight * 0.5);

    canvas.drawRect(Rect.fromLTWH(padding, padding, size.width - padding * 2, size.height - padding * 2), linePaint);
  }

  void _drawGroundSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 3;
    final double scaleFactor = size.width / 400;
    final double fontSize = (11 * scaleFactor).clamp(9.0, 14.0);
    final smallStyle = textStyle.copyWith(fontSize: fontSize);
    double y = padding;

    void drawLabel(String text, double x, double labelY, {TextStyle? style}) {
      final textSpan = TextSpan(text: text, style: style ?? smallStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, labelY));
    }

    void drawLine(double x1, double x2, double lineY) {
      canvas.drawLine(Offset(x1, lineY), Offset(x2, lineY), linePaint);
    }

    double col1 = size.width * 0.15;
    double col2 = size.width * 0.45;
    double col3 = size.width * 0.75;

    // Row 1: facility, ground N, type, a, tail
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('ground, N', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 2: at, location, ready to taxi with info, ATIS
    drawLabel('at', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel(', ready to taxi with info', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 3: empty for notes
    drawLine(col1, size.width - padding, y + rowHeight * 0.5);

    canvas.drawRect(Rect.fromLTWH(padding, padding, size.width - padding * 2, size.height - padding * 2), linePaint);
  }

  void _drawTowerSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 3;
    final double scaleFactor = size.width / 400;
    final double fontSize = (11 * scaleFactor).clamp(9.0, 14.0);
    final smallStyle = textStyle.copyWith(fontSize: fontSize);
    double y = padding;

    void drawLabel(String text, double x, double labelY, {TextStyle? style}) {
      final textSpan = TextSpan(text: text, style: style ?? smallStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, labelY));
    }

    void drawLine(double x1, double x2, double lineY) {
      canvas.drawLine(Offset(x1, lineY), Offset(x2, lineY), linePaint);
    }

    double col1 = size.width * 0.15;
    double col2 = size.width * 0.45;
    double col3 = size.width * 0.75;

    // Row 1: facility, tower N, type, a, tail
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('tower, N', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 2: at runway, runway, ready for takeoff
    drawLabel('at runway', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1 + size.width * 0.12, col2 - 10, y + rowHeight * 0.5);
    drawLabel(', ready for takeoff.', col2, y + rowHeight * 0.35);
    y += rowHeight;

    // Row 3: empty for notes
    drawLine(col1, size.width - padding, y + rowHeight * 0.5);

    canvas.drawRect(Rect.fromLTWH(padding, padding, size.width - padding * 2, size.height - padding * 2), linePaint);
  }

  void _drawDepartureSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 3;
    final double scaleFactor = size.width / 400;
    final double fontSize = (11 * scaleFactor).clamp(9.0, 14.0);
    final smallStyle = textStyle.copyWith(fontSize: fontSize);
    double y = padding;

    void drawLabel(String text, double x, double labelY, {TextStyle? style}) {
      final textSpan = TextSpan(text: text, style: style ?? smallStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, labelY));
    }

    void drawLine(double x1, double x2, double lineY) {
      canvas.drawLine(Offset(x1, lineY), Offset(x2, lineY), linePaint);
    }

    double col1 = size.width * 0.15;
    double col2 = size.width * 0.45;
    double col3 = size.width * 0.75;

    // Row 1: facility, departure N, type, a, tail
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('departure, N', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 2: at, altitude, climbing to, assigned alt
    drawLabel('at', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel(', climbing to', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 3: heading
    drawLabel('heading', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1 + size.width * 0.10, size.width - padding, y + rowHeight * 0.5);

    canvas.drawRect(Rect.fromLTWH(padding, padding, size.width - padding * 2, size.height - padding * 2), linePaint);
  }

  void _drawApproachSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 3;
    final double scaleFactor = size.width / 400;
    final double fontSize = (11 * scaleFactor).clamp(9.0, 14.0);
    final smallStyle = textStyle.copyWith(fontSize: fontSize);
    double y = padding;

    void drawLabel(String text, double x, double labelY, {TextStyle? style}) {
      final textSpan = TextSpan(text: text, style: style ?? smallStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, labelY));
    }

    void drawLine(double x1, double x2, double lineY) {
      canvas.drawLine(Offset(x1, lineY), Offset(x2, lineY), linePaint);
    }

    double col1 = size.width * 0.15;
    double col2 = size.width * 0.45;
    double col3 = size.width * 0.75;

    // Row 1: facility, approach N, type, a, tail
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('approach, N', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 2: distance, miles, direction, at, altitude
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('miles', col2, y + rowHeight * 0.35);
    drawLine(col2 + size.width * 0.10, col3 - 10, y + rowHeight * 0.5);
    drawLabel('at', col3, y + rowHeight * 0.35);
    drawLine(col3 + size.width * 0.05, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 3: landing, airport, with info, ATIS
    drawLabel('landing', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1 + size.width * 0.10, col2 - 10, y + rowHeight * 0.5);
    drawLabel('with info', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);

    canvas.drawRect(Rect.fromLTWH(padding, padding, size.width - padding * 2, size.height - padding * 2), linePaint);
  }

  void _drawTowerArrivalSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 3;
    final double scaleFactor = size.width / 400;
    final double fontSize = (11 * scaleFactor).clamp(9.0, 14.0);
    final smallStyle = textStyle.copyWith(fontSize: fontSize);
    double y = padding;

    void drawLabel(String text, double x, double labelY, {TextStyle? style}) {
      final textSpan = TextSpan(text: text, style: style ?? smallStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, labelY));
    }

    void drawLine(double x1, double x2, double lineY) {
      canvas.drawLine(Offset(x1, lineY), Offset(x2, lineY), linePaint);
    }

    double col1 = size.width * 0.15;
    double col2 = size.width * 0.45;
    double col3 = size.width * 0.75;

    // Row 1: facility, tower N, type, a, tail
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('tower, N', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 2: location, for runway, runway
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('for runway', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 3: with info, ATIS
    drawLabel('with info', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1 + size.width * 0.12, size.width - padding, y + rowHeight * 0.5);

    canvas.drawRect(Rect.fromLTWH(padding, padding, size.width - padding * 2, size.height - padding * 2), linePaint);
  }

  void _drawGroundLandingSheet(Canvas canvas, Size size, Paint linePaint, TextStyle textStyle) {
    final double padding = 16;
    final double rowHeight = (size.height - padding * 2) / 3;
    final double scaleFactor = size.width / 400;
    final double fontSize = (11 * scaleFactor).clamp(9.0, 14.0);
    final smallStyle = textStyle.copyWith(fontSize: fontSize);
    double y = padding;

    void drawLabel(String text, double x, double labelY, {TextStyle? style}) {
      final textSpan = TextSpan(text: text, style: style ?? smallStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, labelY));
    }

    void drawLine(double x1, double x2, double lineY) {
      canvas.drawLine(Offset(x1, lineY), Offset(x2, lineY), linePaint);
    }

    double col1 = size.width * 0.15;
    double col2 = size.width * 0.45;
    double col3 = size.width * 0.75;

    // Row 1: facility, ground N, type, a, tail
    drawLine(col1, col2 - 10, y + rowHeight * 0.5);
    drawLabel('ground, N', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 2: clear of runway, runway, at taxiway, intersection
    drawLabel('clear of runway', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1 + size.width * 0.18, col2 - 10, y + rowHeight * 0.5);
    drawLabel('at taxiway', col2, y + rowHeight * 0.35);
    drawLine(col3, size.width - padding, y + rowHeight * 0.5);
    y += rowHeight;

    // Row 3: taxi to, destination
    drawLabel('taxi to', col1 - size.width * 0.03, y + rowHeight * 0.35);
    drawLine(col1 + size.width * 0.10, size.width - padding, y + rowHeight * 0.5);

    canvas.drawRect(Rect.fromLTWH(padding, padding, size.width - padding * 2, size.height - padding * 2), linePaint);
  }

  @override
  bool shouldRepaint(covariant _BackgroundSheetPainter oldDelegate) {
    return oldDelegate.sheet != sheet || oldDelegate.isDark != isDark;
  }
}
