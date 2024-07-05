import 'package:avaremp/wnb.dart';
import 'package:avaremp/storage.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'constants.dart';

class WnbScreen extends StatefulWidget {
  const WnbScreen({super.key});
  @override
  WnbScreenState createState() => WnbScreenState();
}

class WnbScreenState extends State<WnbScreen> {

  String? _selected;
  Wnb _wnb = Wnb.empty();
  double _currentX = 0;
  double _currentY = 0;
  bool _editing = false;
  final List<Offset> _plotData = [];

  Widget _makeContent(List<Wnb>? items) {

    String inStorage = Storage().settings.getWnb();

    if(null != items && (!_editing)) {
      if(items.isEmpty) {
        _wnb = Wnb.empty();
        _plotData.clear();
      }
      else {
        _selected = items[0].name; // use first item if nothing in storage
        for (Wnb w in items) {
          if (w.name == inStorage) { // found the wnb
            _selected = w.name;
            _wnb.maxX = w.maxX;
            _wnb.minX = w.minX;
            _wnb.maxY = w.maxY;
            _wnb.minY = w.minY;
            _wnb.items = w.items;
            _plotData.clear();
            _plotData.addAll(Wnb.getPoints(w.points));
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
            child: DropdownButton2<String>( // airport selection
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

    return Padding(padding: const EdgeInsets.all(10), child:SingleChildScrollView(child:
      Column(children:[
        TextFormField(
          enabled: _editing,
          controller: TextEditingController()..text = _wnb.name,
          decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Name"),
          keyboardType: TextInputType.number,
          onFieldSubmitted: (value) {
            setState(() {
              _wnb.name = value;
            });
            Storage().settings.setWnb(value);
          },
        ),

        AspectRatio(aspectRatio: 1,
          child: Stack(children: [
            Align(alignment: Alignment.bottomRight, child:SizedBox(width: 100, child:TextFormField(
              enabled: _editing,
              controller: TextEditingController()..text = _wnb.maxX.toString(),
              decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Arm Max."),
              keyboardType: TextInputType.number,
              onFieldSubmitted: (value) {
                try {
                  setState(() {
                    double val = double.parse(value);
                    if(val > _wnb.minX) {
                      _wnb.maxX = val;
                    }
                  });
                }
                catch (e) {}
              },
            ))),
            Align(alignment: Alignment.bottomLeft, child:SizedBox(width: 100, child:TextFormField(
                enabled: _editing,
                controller: TextEditingController()..text = _wnb.minX.toString(),
                decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Arm Min."),
                keyboardType: TextInputType.number,
                onFieldSubmitted: (value) {
                  try {
                    setState(() {
                      double val = double.parse(value);
                      if (val < _wnb.maxX) {
                        _wnb.minX = val;
                      }
                    });
                  }
                  catch (e) {}
                }
            ))),
            Align(alignment: Alignment.topCenter, child:SizedBox(width: 100, child:TextFormField(
              enabled: _editing,
              controller: TextEditingController()..text = _wnb.maxY.toString(),
                decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Weight Max."),
                keyboardType: TextInputType.number,
                onFieldSubmitted: (value) {
                  try {
                    setState(() {
                      double val = double.parse(value);
                      if(val > _wnb.minY) {
                        _wnb.maxY = val;
                      }
                    });
                  }
                  catch (e) {}
                },
            ))),
            Align(alignment: Alignment.bottomCenter, child:SizedBox(width: 100, child:TextFormField(
              enabled: _editing,
              controller: TextEditingController()..text = _wnb.minY.toString(),
                decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Weight Min."),
                keyboardType: TextInputType.number,
                onFieldSubmitted: (value) {
                  try {
                    setState(() {
                      double val = double.parse(value);
                      if(val < _wnb.maxY) {
                        _wnb.minY = val;
                      }
                    });
                  }
                  catch (e) {}
                },
            ))),
            Align(alignment: Alignment.centerLeft, child:SizedBox(width: 60, child:Text("Arm:\n ${_currentX.round()}\nWeight:\n ${_currentY.round()}", style: const TextStyle(fontSize: 10, color: Colors.yellow)))),

            Container(padding: const EdgeInsets.all(60),
              child:LayoutBuilder(builder: (context, constraints) {

                Offset pixelToCoordinate(Offset offset, BoxConstraints constraints) {
                  double reservedSize = 0; // size reserved for label tiles
                  return Offset(
                    _wnb.minX + (_wnb.maxX - _wnb.minX) * offset.dx / (constraints.maxWidth - reservedSize * 2),
                    (_wnb.maxY + _wnb.minY) - (_wnb.minY + (_wnb.maxY - _wnb.minY) * offset.dy / (constraints.maxHeight - reservedSize * 2)));
                }

                return ScatterChart(
                  ScatterChartData(
                    titlesData: const FlTitlesData(
                      show: false, // do not show. too crammed
                    ),
                    scatterSpots: _plotData.asMap().entries.map((e) {
                      return ScatterSpot(e.value.dx, e.value.dy, dotPainter: getPaint(4, Colors.yellow),);
                    }).toList(),
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
                        if(event.localPosition != null) {
                          Offset offs = pixelToCoordinate(event.localPosition!, constraints);
                          setState(() {
                            _currentX = offs.dx;
                            _currentY = offs.dy;
                          });
                        }

                        if(event is FlTapUpEvent && _editing) {
                          if (touchResponse != null) {
                            // existing spot, delete
                            ScatterTouchedSpot? spot = touchResponse.touchedSpot;
                            if(spot != null) {
                              setState(() {
                                _plotData.removeAt(spot.spotIndex);
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


  @override
  Widget build(BuildContext context) {
    List<Wnb>? data = Storage().realmHelper.getAllWnb();
    return _makeContent(data);
  }
}


