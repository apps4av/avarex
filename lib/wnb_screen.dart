import 'package:avaremp/wnb.dart';
import 'package:avaremp/storage.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:point_in_polygon/point_in_polygon.dart';
import 'constants.dart';

class WnbScreen extends StatefulWidget {
  const WnbScreen({super.key});
  @override
  WnbScreenState createState() => WnbScreenState();
}

class WnbScreenState extends State<WnbScreen> {

  String? _selected;
  Wnb _wnb = Wnb.empty(); // to keep current editing
  bool _editing = false;
  final List<Offset> _plotData = [];
  Offset _cgData = const Offset(0, 0);


  Widget _makeContent(List<Wnb>? items) {

    String inStorage = Storage().settings.getWnb();

    if(null != items) {
      if(!_editing) {
        if (items.isEmpty) {
          _wnb = Wnb.empty(); // this will reset the screen
          _plotData.clear();
          _cgData = const Offset(0, 0);
        }
        else {
          _selected = items[0].name; // use first item if nothing in storage
          for (Wnb w in items) {
            if (w.name == inStorage || inStorage.isEmpty) { // found the wnb
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
            title: const Text("W&B"),
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
            child: DropdownButton2<String>( // wnb selection
              buttonStyleData: ButtonStyleData(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Constants.dropDownButtonBackgroundColor),
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
        return ScatterSpot(e.value.dx, e.value.dy, dotPainter: getPaint(4, Colors.yellow),);
      }).toList();
      spots.insert(0, ScatterSpot(_cgData.dx, _cgData.dy, dotPainter: getPaint(6, _isInside() ? Colors.green : Colors.red),));
      return spots;
    }

    return Padding(padding: const EdgeInsets.all(10), child:SingleChildScrollView(child:
      Column(children:[
        TextFormField(
          enabled: _editing,
          controller: TextEditingController()..text = _wnb.name,
          decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Name"),
          keyboardType: TextInputType.number,
          onChanged: (value) {
           _wnb.name = value;
          },
        ),

        AspectRatio(aspectRatio: 1,
          child: Stack(children: [
            Align(alignment: Alignment.bottomRight, child:SizedBox(width: 100, child:TextFormField(
              enabled: _editing,
              controller: TextEditingController()..text = _wnb.maxX.toString(),
              decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Arm Max."),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                try {
                  double val = double.parse(value);
                  if(val > _wnb.minX) {
                    _wnb.maxX = val;
                  }
                }
                catch (e) {}
              },
            ))),
            Align(alignment: Alignment.bottomLeft, child:SizedBox(width: 100, child:TextFormField(
                enabled: _editing,
                controller: TextEditingController()..text = _wnb.minX.toString(),
                decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Arm Min."),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  try {
                    double val = double.parse(value);
                    if (val < _wnb.maxX) {
                      _wnb.minX = val;
                    }
                  }
                  catch (e) {}
                }
            ))),
            Align(alignment: Alignment.topCenter, child:SizedBox(width: 100, child:TextFormField(
              enabled: _editing,
              controller: TextEditingController()..text = _wnb.maxY.toString(),
                decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Weight Max."),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  try {
                    double val = double.parse(value);
                    if(val > _wnb.minY) {
                      _wnb.maxY = val;
                    }
                  }
                  catch (e) {}
                },
            ))),
            Align(alignment: Alignment.bottomCenter, child:SizedBox(width: 100, child:TextFormField(
              enabled: _editing,
              controller: TextEditingController()..text = _wnb.minY.toString(),
                decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Weight Min."),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  try {
                      double val = double.parse(value);
                      if(val < _wnb.maxY) {
                        _wnb.minY = val;
                      }
                  }
                  catch (e) {}
                },
            ))),

            Container(padding: const EdgeInsets.fromLTRB(10, 60, 10, 60),
              child:LayoutBuilder(builder: (context, constraints) {

                Offset pixelToCoordinate(Offset offset, BoxConstraints constraints) {
                  double reservedSize = 44 + 16; // size reserved for label tiles
                  return Offset(
                    _wnb.minX + (_wnb.maxX - _wnb.minX) * (offset.dx) / (constraints.maxWidth - reservedSize),
                    (_wnb.maxY + _wnb.minY) - (_wnb.minY + (_wnb.maxY - _wnb.minY) * (offset.dy) / (constraints.maxHeight - reservedSize)));
                }

                return ScatterChart(
                  ScatterChartData(
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(axisNameSize: 16, axisNameWidget: Text("Weight"), sideTitles: SideTitles(reservedSize: 44, showTitles: true)),
                      bottomTitles: AxisTitles(axisNameSize: 16, axisNameWidget: Text("Arm"),  sideTitles: SideTitles(reservedSize: 44, showTitles: true)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(reservedSize: 0, showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(reservedSize: 0, showTitles: false)),
                      show: true, // do not show. too crammed
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
                      getDrawingHorizontalLine: (value) => FlLine(color: _editing ? Colors.white : Colors.grey,),
                      drawVerticalLine: true,
                      checkToShowVerticalLine: (value) => true,
                      getDrawingVerticalLine: (value) => FlLine(color: _editing ? Colors.white : Colors.grey,),
                    ),

                    scatterTouchData: ScatterTouchData(
                      touchSpotThreshold: 10, // touch for mobile finger width
                      enabled: true,
                      handleBuiltInTouches: false,
                      touchCallback: (FlTouchEvent event, ScatterTouchResponse? touchResponse) {
                        if(event is FlTapUpEvent && _editing) {
                          if (touchResponse != null) {
                            // existing spot, delete
                            ScatterTouchedSpot? spot = touchResponse.touchedSpot;
                            if(spot != null) {
                              setState(() {
                                if(spot.spotIndex > 0) {
                                  _plotData.removeAt(spot.spotIndex - 1); // first spot is CG
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
                  ),);
                }
              )
            ),
          ],
        ),
      ),

      const Divider(),

      _makeLines(),

      Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [

            Padding(padding: const EdgeInsets.all(20), child: Dismissible(key: GlobalKey(),
                background: const Icon(Icons.delete_forever),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) {
                  String? entry = _selected;
                  if(null != entry) {
                    Storage().realmHelper.deleteWnb(entry);
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
                    // save
                    _wnb.points = Wnb.getPointsAsString(_plotData);
                    _wnb.items = _wnb.items;
                    Storage().realmHelper.addWnb(_wnb).then((value) => setState(() {
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

      ])));
  }


  bool _isInside() {
    List<Point> points = _plotData.map((e) => Point(x: e.dx, y: e.dy)).toList();
    Point point = Point(x: _cgData.dx, y: _cgData.dy);
    return Poly.isPointInPolygon(point, points);
  }

  Widget _makeLines() {

    List<Widget> lines = [];
    double totalWeight = 0;
    double totalMoment = 0;

    // add items
    for(int index = 0; index < _wnb.items.length; index++) {

      String item = _wnb.items[index];
      WnbItem wnbItem = WnbItem.fromJson(item);
      totalWeight += wnbItem.weight;
      totalMoment += wnbItem.weight * wnbItem.arm;

      lines.add(Row(children: [
        Flexible(flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10), child: TextFormField(
              enabled: _editing,
              decoration: index == 0 ? const InputDecoration(border: UnderlineInputBorder(), labelText: "Item") : null,
              controller: TextEditingController()..text = wnbItem.description,
              onChanged: (value) {
                wnbItem.description = value;
                _wnb.items[index] = wnbItem.toJson();
              },
            ))),
        Flexible(flex: 1,
            child: Padding(
                padding: const EdgeInsets.all(10), child: TextFormField(
              controller: TextEditingController()..text = wnbItem.weight.toString(),
              keyboardType: TextInputType.number,
              enabled: _editing,
              decoration: index == 0 ? const InputDecoration(border: UnderlineInputBorder(), labelText: "Weight") : null,
              onChanged: (value) {
                try {
                  wnbItem.weight = double.parse(value);
                  _wnb.items[index] = wnbItem.toJson();
                }
                catch (e) {}
              },
            ))),
        Flexible(flex: 1,
            child: Padding(
                padding: const EdgeInsets.all(10), child: TextFormField(
              controller: TextEditingController()..text = wnbItem.arm.toString(),
              enabled: _editing,
              keyboardType: TextInputType.number,
              decoration: index == 0 ? const InputDecoration(border: UnderlineInputBorder(), labelText: "Arm") : null,
              onChanged: (value) {
                try {
                  wnbItem.arm = double.parse(value);
                  _wnb.items[index] = wnbItem.toJson();
                }
                catch (e) {}
              },
            ))),
        Flexible(flex: 1,
            child: Padding(padding: const EdgeInsets.all(10), child: TextFormField(
              enabled: false,
              decoration: index == 0 ? const InputDecoration(border: UnderlineInputBorder(), labelText: "Moment") : null,
              controller: TextEditingController()..text = (wnbItem.weight * wnbItem.arm).toStringAsFixed(1),
            ))),
      ]),);
    }

    _cgData = totalWeight == 0 ? const Offset(0, 0) : Offset((totalMoment / totalWeight), totalWeight); // save div by 0
    lines.add(Row(
      children: [
        Flexible(flex: 2, child: Padding(padding: const EdgeInsets.all(10), child: TextFormField(enabled: false, initialValue: "Total"))),
        Flexible(flex: 1, child: Padding(padding: const EdgeInsets.all(10), child: TextFormField(enabled: false, controller: TextEditingController()..text = _cgData.dy.toStringAsFixed(1)))),
        Flexible(flex: 1, child: Padding(padding: const EdgeInsets.all(10), child: TextFormField(enabled: false, controller: TextEditingController()..text = _cgData.dx.toStringAsFixed(1)))),
        Flexible(flex: 1, child: Padding(padding: const EdgeInsets.all(10), child: TextFormField(enabled: false, controller: TextEditingController()..text = totalMoment.toStringAsFixed(0)))),
      ])
    );
    return Column(children: lines);
  }

  @override
  Widget build(BuildContext context) {
    List<Wnb>? data = Storage().realmHelper.getAllWnb();
    return _makeContent(data);
  }
}


