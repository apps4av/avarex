import 'package:avaremp/constants.dart';
import 'package:avaremp/plan_create_widget.dart';
import 'package:avaremp/plan_file_widget.dart';
import 'package:avaremp/plan_item_widget.dart';
import 'package:avaremp/plan_line_widget.dart';
import 'package:avaremp/plan_load_save_widget.dart';
import 'package:avaremp/plan_manage_widget.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'data/altitude_profile.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlanScreenState();
}

class PlanScreenState extends State<PlanScreen> {


  final CarouselSliderController _controller = CarouselSliderController();

  Widget _makeContent() {

    Widget loadSavePage = const PlanLoadSaveWidget();

    Widget createPage = const PlanCreateWidget();

    Widget filePage = const PlanFileWidget();

    Widget managePage = const PlanManageWidget();

    List<Widget> pages = [];
    pages.add(loadSavePage);
    pages.add(createPage);
    pages.add(filePage);
    pages.add(managePage);

    // carousel
    List<Card> cards = [];
    for (Widget page in pages) {
      cards.add(Card(
          child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.expand(
                  child: page
              )
          )
      ));
    }

    return Container(
        padding: const EdgeInsets.all(5),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
        ),
        child:
          Column(children: [
            // various info
            Expanded(flex: 8, child: CarouselSlider(
              carouselController: _controller,
              items: cards,
              options: CarouselOptions(
                viewportFraction: 1,
                enlargeFactor: 0.5,
                enableInfiniteScroll: false,
                enlargeCenterPage: true,
                aspectRatio: Constants.carouselAspectRatio(context),
              ),
            )),
          // add various buttons that expand to diagram
          Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisAlignment: MainAxisAlignment.end, children:[
              TextButton(
                  child: const Text("Load & Save"),
                  onPressed: () => _controller.animateToPage(0)
              ),
              TextButton(
                  child: const Text("Create"),
                  onPressed: () => _controller.animateToPage(1)
              ),
              TextButton(
                  child: const Text("Brief & File"),
                  onPressed: () => _controller.animateToPage(2)
              ),
              TextButton(
                  child: const Text("Manage"),
                  onPressed: () => _controller.animateToPage(3)
              ),
            ])),
          ),
        ],
          )
    );

  }

  @override
  Widget build(BuildContext context) {
    final PlanRoute route = Storage().route;

    double height = 0;
    double bottom = Constants.bottomPaddingSize(context);

    // user can rearrange widgets
    return Container(padding: EdgeInsets.fromLTRB(5, height + 10, 5, bottom),
      child: Stack(children:[
        Column(
          children: [
            Expanded(flex: 1,
              child: ValueListenableBuilder<int>( // update in plan change
                valueListenable: route.change,
                builder: (context, value, _) {
                  return ListTile( // header
                    key: Key(Storage().getKey()),
                    leading: const Icon(Icons.summarize_outlined),
                    title: PlanLineWidgetState.getHeading(),
                    subtitle: PlanLineWidgetState.getFieldsFromCalculations(Storage().route.totalCalculations));
                }
              )
            ), // heading for dist, time etc.
            Expanded(flex: 5, child: ReorderableListView(
              scrollDirection: Axis.vertical,
              buildDefaultDragHandles: false,
              children: <Widget>[
                for(int index = 0; index < route.length; index++)
                ReorderableDelayedDragStartListener(
                  index: index,
                  key: Key(index.toString()),
                  child: GestureDetector(child:
                    Dismissible( // able to delete with swipe
                      background: Container(alignment:
                      Alignment.centerRight,child: const Icon(Icons.delete_forever),),
                      key: Key(Storage().getKey()),
                      direction: DismissDirection.endToStart,
                      onDismissed:(direction) {
                        setState(() {
                          route.removeWaypointAt(index);
                        });
                      },
                      child: ValueListenableBuilder<int>( // update in plan change
                        valueListenable: route.change,
                        builder: (context, value, _) {
                          return PlanItemWidget(
                            waypoint: route.getWaypointAt(index),
                            current: route.isCurrent(index),
                            onTap: () {
                              setState(() {
                                Storage().route.setCurrentWaypoint(index);
                              });
                            },
                          );
                       },
                    )
                  ))),
                ],
                onReorder: (int oldIndex, int newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    route.moveWaypoint(oldIndex, newIndex);
                  });
                })
              ),
              Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(
                children:[ // header
                  TextButton(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        useSafeArea: true,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (BuildContext context) {
                          return _makeContent();
                        },
                      ).then((value) => setState(() {})); // this is important so if modal changes plan then we update it here
                    },
                    child: const Text("Actions"),),
                  Padding(padding: const EdgeInsets.all(5), child:SizedBox(width: Constants.screenWidth(context) / 10, child: TextFormField(
                      keyboardType: TextInputType.numberWithOptions(signed: true, decimal: true),
                      onChanged: (value) {
                        double? pValue = double.tryParse(value);
                        Storage().settings.setTas(pValue ?? Storage().settings.getTas());
                      },
                      controller: TextEditingController()..text = Storage().settings.getTas().round().toString(),
                      decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "ASpd")
                  ))),
                  Padding(padding: const EdgeInsets.all(5), child: SizedBox(width: Constants.screenWidth(context) / 10, child: TextFormField(
                    keyboardType: TextInputType.numberWithOptions(signed: true, decimal: true),
                    onChanged: (value) {
                      double? pValue = double.tryParse(value);
                      Storage().settings.setFuelBurn(pValue ?? Storage().settings.getFuelBurn());
                    },
                    controller: TextEditingController()..text = Storage().settings.getFuelBurn().toString(),
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "GPH")
                  ))),
                  Padding(padding: const EdgeInsets.all(5), child: SizedBox(width: Constants.screenWidth(context) / 10, child: TextFormField(
                      keyboardType: TextInputType.numberWithOptions(signed: true, decimal: true),
                      onChanged: (value) {
                        int? pValue = int.tryParse(value);
                        pValue ??= 3000;
                        Storage().route.altitude = pValue.toString();
                      },
                      controller: TextEditingController()..text = Storage().route.altitude,
                      decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Alt")
                  ))),

                  IconButton(icon: const Icon(Icons.show_chart), onPressed:() {
                    showDialog(context: context,
                      builder: (BuildContext context) => Dialog.fullscreen(
                        child: FutureBuilder(
                          future: AltitudeProfile.getAltitudeProfile(Storage().route.getPathNextHighResolution()),
                          builder: (context, snapshot) {
                            return _makeAltitudeDiagram(snapshot.data);
                          }
                      )));
                  }),
                  const Tooltip(showDuration: Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "To delete a waypoint, swipe it left.\nTo move a waypoint up/down, long press to grab and move it.", child: Icon(Icons.info)),
                ]
              )
            ))
          ]
        )
      ]
      ),
    );
  }


  Widget _makeAltitudeDiagram(List<double>? data) {
    if(null == data) {
      return const Center(child: CircularProgressIndicator());
    }

    double square = Constants.isPortrait(context) ? Constants.screenWidth(context) : Constants.screenHeight(context);

    return Stack(children:[
      const Align(alignment: Alignment.topLeft, child: Padding(padding: EdgeInsets.all(10), child:Text("Plan Altitude Profile ft/NM"))),
      Padding(padding: const EdgeInsets.all(20), child: SizedBox(width : square, height : square, child: AltitudeProfile.makeChart(data))),
      Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 36, color: Colors.white))),
    ]
    );
  }

}

