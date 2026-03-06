import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:avaremp/wnb/wnb.dart';
import 'package:avaremp/storage.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:point_in_polygon/point_in_polygon.dart';
import '../constants.dart';

class WnbScreen extends StatefulWidget {
  const WnbScreen({super.key});
  @override
  WnbScreenState createState() => WnbScreenState();
}

class WnbScreenState extends State<WnbScreen> {

  String? _selected;
  Wnb _wnb = Wnb.empty();
  bool _editing = false;
  final List<Offset> _plotData = [];
  Offset _cgData = const Offset(0, 0);


  Widget _makeContent(List<Wnb>? items) {

    String inStorage = Storage().settings.getWnb();

    if(null != items) {
      if(!_editing) {
        if (items.isEmpty) {
          _wnb = Wnb.empty();
          _plotData.clear();
          _cgData = const Offset(0, 0);
        }
        else {
          _selected = items[0].name;
          for (Wnb w in items) {
            if (w.name == inStorage || inStorage.isEmpty) {
              _selected = w.name;
              _wnb.maxX = w.maxX;
              _wnb.minX = w.minX;
              _wnb.maxY = w.maxY;
              _wnb.minY = w.minY;
              _wnb.items = w.items;
              _wnb.name = w.name;
              _plotData.clear();
              _plotData.addAll(Wnb.getPoints(w.points));
            }
          }
        }
      }
    }

    return Scaffold(
        appBar: AppBar(
            backgroundColor: Constants.appBarBackgroundColor,
            title: const Text("Weight & Balance"),
            actions: _makeAction(items)
        ),
        body: _makeBody(items)
    );
  }

  List<Widget> _makeAction(List<Wnb>? items) {
    if(null == items || items.isEmpty) {
      return [];
    }
    return [
      Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        child: DropdownButtonHideUnderline(
            child: DropdownButton2<String>(
              buttonStyleData: ButtonStyleData(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
              ),
              dropdownStyleData: DropdownStyleData(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
              ),
              isExpanded: false,
              value: _selected,
              items: items.map((Wnb e) => DropdownMenuItem<String>(value: e.name, child: Text(e.name, style: TextStyle(fontSize: Constants.dropDownButtonFontSize)))).toList(),
              onChanged: (value) {
                setState(() {
                  _selected = value;
                  Storage().settings.setWnb(value!);
                });
              },
            )
        )
    )];
  }

  Widget _makeBody(List<Wnb>? items) {

    FlDotPainter getPaint(double size, Color color) {
      return FlDotCirclePainter(
        color: color,
        radius: size,
      );
    }

    List<ScatterSpot> makeSpotData() {
      List<ScatterSpot> spots = _plotData.asMap().entries.map((e) {
        return ScatterSpot(e.value.dx, e.value.dy, dotPainter: getPaint(4, Colors.blueAccent),);
      }).toList();
      spots.insert(0, ScatterSpot(_cgData.dx, _cgData.dy, dotPainter: getPaint(8, _isInside() ? Colors.green : Colors.red),));
      return spots;
    }

    _calculateCG();
    bool isInside = _isInside();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Card
          Card(
            color: isInside ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isInside ? Icons.check_circle : Icons.warning,
                    color: isInside ? Colors.green : Colors.red,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isInside ? "Within Limits" : "Outside Limits",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isInside ? Colors.green : Colors.red,
                          ),
                        ),
                        Text(
                          "CG: ${_cgData.dx.toStringAsFixed(2)} | Weight: ${_cgData.dy.toStringAsFixed(1)} lbs",
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Profile Name
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextFormField(
                enabled: _editing,
                controller: TextEditingController()..text = _wnb.name,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Profile Name",
                  prefixIcon: Icon(Icons.airplanemode_active),
                ),
                onChanged: (value) {
                  _wnb.name = value;
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Chart Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.show_chart, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        "CG Envelope",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      if(_editing)
                        Text("Tap to add/remove points", style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Envelope limits
                  Row(
                    children: [
                      Expanded(child: _buildLimitField("Arm Min", _wnb.minX, (v) => _wnb.minX = v)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildLimitField("Arm Max", _wnb.maxX, (v) => _wnb.maxX = v)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildLimitField("Wt Min", _wnb.minY, (v) => _wnb.minY = v)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildLimitField("Wt Max", _wnb.maxY, (v) => _wnb.maxY = v)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Chart
                  AspectRatio(
                    aspectRatio: 1.2,
                    child: LayoutBuilder(builder: (context, constraints) {
                      Offset pixelToCoordinate(Offset offset, BoxConstraints constraints) {
                        double reservedSize = 44 + 16;
                        return Offset(
                          _wnb.minX + (_wnb.maxX - _wnb.minX) * (offset.dx) / (constraints.maxWidth - reservedSize),
                          (_wnb.maxY + _wnb.minY) - (_wnb.minY + (_wnb.maxY - _wnb.minY) * (offset.dy) / (constraints.maxHeight - reservedSize)));
                      }

                      return ScatterChart(
                        ScatterChartData(
                          titlesData: const FlTitlesData(
                            leftTitles: AxisTitles(axisNameSize: 16, axisNameWidget: Text("Weight (lbs)"), sideTitles: SideTitles(reservedSize: 44, showTitles: true)),
                            bottomTitles: AxisTitles(axisNameSize: 16, axisNameWidget: Text("Arm (in)"),  sideTitles: SideTitles(reservedSize: 44, showTitles: true)),
                            rightTitles: AxisTitles(sideTitles: SideTitles(reservedSize: 0, showTitles: false)),
                            topTitles: AxisTitles(sideTitles: SideTitles(reservedSize: 0, showTitles: false)),
                            show: true,
                          ),
                          scatterSpots: makeSpotData(),
                          minX: _wnb.minX.toDouble(),
                          minY: _wnb.minY.toDouble(),
                          maxX: _wnb.maxX.toDouble(),
                          maxY: _wnb.maxY.toDouble(),
                          gridData: FlGridData(
                            show: true,
                            drawHorizontalLine: true,
                            checkToShowHorizontalLine: (value) => true,
                            getDrawingHorizontalLine: (value) => FlLine(color: Theme.of(context).colorScheme.outlineVariant),
                            drawVerticalLine: true,
                            checkToShowVerticalLine: (value) => true,
                            getDrawingVerticalLine: (value) => FlLine(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          scatterTouchData: ScatterTouchData(
                            touchSpotThreshold: 10,
                            enabled: true,
                            handleBuiltInTouches: false,
                            touchCallback: (FlTouchEvent event, ScatterTouchResponse? touchResponse) {
                              if(event is FlTapUpEvent && _editing) {
                                if (touchResponse != null) {
                                  ScatterTouchedSpot? spot = touchResponse.touchedSpot;
                                  if(spot != null) {
                                    setState(() {
                                      if(spot.spotIndex > 0) {
                                        _plotData.removeAt(spot.spotIndex - 1);
                                      }
                                    });
                                  }
                                  else {
                                    setState(() {
                                      _plotData.add(pixelToCoordinate(event.details.localPosition, constraints));
                                    });
                                  }
                                }
                              }
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Weight Items Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.scale, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        "Weight Items",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _makeLines(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action Buttons
          Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [

                Padding(padding: const EdgeInsets.all(20), child: Dismissible(key: GlobalKey(),
                    background: const Icon(Icons.delete_forever),
                    direction: DismissDirection.endToStart,
                    onDismissed: (direction) {
                      String? entry = _selected;
                      if(null != entry) {
                        UserDatabaseHelper.db.deleteWnb(entry);
                      }
                      Storage().settings.setWnb("");
                      setState(() {
                        _selected = null;
                        _editing = false;
                      });
                    },
                    child: const Column(children:[Icon(Icons.swipe_left), Text("Delete", style: TextStyle(fontSize: 8))])
                )),

                TextButton(
                    onPressed: () {
                      if(_editing) {
                        _wnb.points = Wnb.getPointsAsString(_plotData);
                        _wnb.items = _wnb.items;
                        UserDatabaseHelper.db.addWnb(_wnb).then((value) => setState(() {
                          Storage().settings.setWnb(_wnb.name);
                          _editing = !_editing;
                        }));
                      }
                      else {
                        setState(() {
                          _editing = !_editing;
                        });
                      }
                    },
                    child: Text(_editing ? "Save" : "Edit")
                ),

              ])
            ),
        ],
      ),
    );
  }

  Widget _buildLimitField(String label, double value, Function(double) onChanged) {
    return TextFormField(
      enabled: _editing,
      controller: TextEditingController()..text = value.toString(),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
      onChanged: (v) {
        try {
          double val = double.parse(v);
          onChanged(val);
        } catch (e) {
          // ignore
        }
      },
      onFieldSubmitted: (v) {
        try {
          double val = double.parse(v);
          setState(() {
            onChanged(val);
          });
        } catch (e) {
          Toast.showToast(context, "Invalid number", const Icon(Icons.error, color: Colors.red), 3);
        }
      },
    );
  }

  bool _isInside() {
    List<Point> points = _plotData.map((e) => Point(x: e.dx, y: e.dy)).toList();
    Point point = Point(x: _cgData.dx, y: _cgData.dy);
    return Poly.isPointInPolygon(point, points);
  }

  void _calculateCG() {
    double totalWeight = 0;
    double totalMoment = 0;
    for(int index = 0; index < _wnb.items.length; index++) {
      String item = _wnb.items[index];
      WnbItem wnbItem = WnbItem.fromJson(item);
      totalWeight += wnbItem.weight;
      totalMoment += wnbItem.weight * wnbItem.arm;
    }
    _cgData = totalWeight == 0 ? const Offset(0, 0) : Offset((totalMoment / totalWeight), totalWeight);
  }

  Widget _makeLines() {
    List<Widget> lines = [];
    double totalWeight = 0;
    double totalMoment = 0;

    // Header row
    lines.add(
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text("Item", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
            Expanded(flex: 2, child: Text("Weight", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text("Arm", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text("Moment", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
          ],
        ),
      ),
    );

    for(int index = 0; index < _wnb.items.length; index++) {
      String item = _wnb.items[index];
      WnbItem wnbItem = WnbItem.fromJson(item);
      totalWeight += wnbItem.weight;
      totalMoment += wnbItem.weight * wnbItem.arm;

      lines.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextFormField(
                    enabled: _editing,
                    controller: TextEditingController()..text = wnbItem.description,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      wnbItem.description = value;
                      _wnb.items[index] = wnbItem.toJson();
                    },
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextFormField(
                    controller: TextEditingController()..text = wnbItem.weight.toString(),
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    enabled: _editing,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      try {
                        wnbItem.weight = double.parse(value);
                        _wnb.items[index] = wnbItem.toJson();
                      } catch (e) {
                        // ignore
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextFormField(
                    controller: TextEditingController()..text = wnbItem.arm.toString(),
                    enabled: _editing,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      try {
                        wnbItem.arm = double.parse(value);
                        _wnb.items[index] = wnbItem.toJson();
                      } catch (e) {
                        // ignore
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      (wnbItem.weight * wnbItem.arm).toStringAsFixed(0),
                      style: const TextStyle(fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    _cgData = totalWeight == 0 ? const Offset(0, 0) : Offset((totalMoment / totalWeight), totalWeight);

    // Total row
    lines.add(
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _isInside() ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _isInside() ? Colors.green : Colors.red),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text(_cgData.dy.toStringAsFixed(1), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text(_cgData.dx.toStringAsFixed(2), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text(totalMoment.toStringAsFixed(0), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );

    return Column(children: lines);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: UserDatabaseHelper.db.getAllWnb(),
      builder: (BuildContext context, AsyncSnapshot<List<Wnb>?> snapshot) {
        return _makeContent(snapshot.data);
      }
    );
  }
}
