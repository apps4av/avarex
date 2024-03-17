import 'dart:io';
import 'package:avaremp/airport.dart';
import 'package:avaremp/documents_screen.dart';
import 'package:avaremp/gdl90/nexrad_cache.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/pfd_painter.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/airep.dart';
import 'package:avaremp/weather/airsigmet.dart';
import 'package:avaremp/weather/tfr.dart';
import 'package:avaremp/warnings_widget.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path/path.dart';
import 'chart.dart';
import 'constants.dart';
import 'destination.dart';
import 'download_screen.dart';
import 'gps.dart';
import 'longpress_widget.dart';
import 'weather/metar.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<StatefulWidget> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  final List<String> _charts = DownloadScreenState.getCategories();
  LatLng? _previousPosition;
  bool _interacting = false;
  final Ruler _ruler = Ruler();

  String _type = Storage().settings.getChartType();
  int _maxZoom = ChartCategory.chartTypeToZoom(Storage().settings.getChartType());
  MapController? _controller;
  // get layers and states from settings
  final List<String> _layers = Storage().settings.getLayers();
  final List<bool> _layersState = Storage().settings.getLayersState();
  bool _northUp = Storage().settings.getNorthUp();

  Future<bool> showDestination(BuildContext context, Destination destination) async {
    bool? exitResult = await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return LongPressWidget(destination: destination);
      },
    );
    return exitResult ?? false;
  }

  void _handlePress(TapPosition tapPosition, LatLng point) async {
    List<Destination> items = await MainDatabaseHelper.db.findNear(point);
    setState(() {
      showDestination(this.context, items[0]);
    });
  }

  @override
  void initState() {
    _controller = MapController();
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    // save ptz when we switch out
    if(_controller != null) {
      Storage().settings.setZoom(_controller!.camera.zoom);
      Storage().settings.setCenterLatitude(_controller!.camera.center.latitude);
      Storage().settings.setCenterLongitude(
          _controller!.camera.center.longitude);
      Storage().settings.setRotation(_controller!.camera.rotation);
      Storage().gpsChange.removeListener(_listen);
      _previousPosition = null;
      _controller!.dispose();
      _controller = null;
    }
  }

  // this pans camera on move
  void _listen() {
    LatLng cur = Gps.toLatLng(Storage().position);
    _previousPosition ??= cur;
    if(null != _controller) {
      try {
        LatLng diff = LatLng(cur.latitude - _previousPosition!.latitude,
            cur.longitude - _previousPosition!.longitude);
        LatLng now = _controller!.camera.center;
        LatLng next = LatLng(
            now.latitude + diff.latitude, now.longitude + diff.longitude);
        if (!_interacting) { // do not move when user is moving map
          _controller!.moveAndRotate(next, _controller!.camera.zoom,
              _northUp ? 0 : -Storage().position.heading);
        }
      }
      catch (e) {} // addign to lat lon is dangerous
    }

    _previousPosition = Gps.toLatLng(Storage().position);
  }

  @override
  Widget build(BuildContext context) {

    String index = ChartCategory.chartTypeToIndex(_type);
    _maxZoom = ChartCategory.chartTypeToZoom(_type);

    //add layers
    List<Widget> layers = [];
    TileLayer networkLayer = TileLayer(
        urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        tileProvider: FMTC.instance('mapStore').getTileProvider());
    TileLayer chartLayer = TileLayer(
        tms: true,
        maxNativeZoom: _maxZoom,
        tileProvider: ChartTileProvider(),
        urlTemplate: "${Storage().dataDir}/tiles/$index/{z}/{x}/{y}.webp");

    // start from known location
    MapOptions opts = MapOptions(
      initialCenter: LatLng(Storage().settings.getCenterLatitude(), Storage().settings.getCenterLongitude()),
      initialZoom: Storage().settings.getZoom(),
      minZoom: 2, // this is less crazy
      maxZoom: 20, // max for USGS
      interactionOptions: InteractionOptions(flags: _northUp ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.all),  // no rotation in track up
      initialRotation: Storage().settings.getRotation(),
      backgroundColor: Constants.mapBackgroundColor,
      onLongPress: _handlePress,
      onPointerDown: (PointerDownEvent event, position) { // calculate down pointers here
        _ruler.setPointer(event.pointer, position);
      },
      onMapEvent: (MapEvent mapEvent) {
        if (mapEvent is MapEventMoveStart) {
          // do something
          _interacting = true;
        }
        if (mapEvent is MapEventMoveEnd) {
          // do something
          _interacting = false;
        }
      },
    );

    int lIndex = _layers.indexOf('OSM');
    if(_layersState[lIndex]) {
      layers.add(networkLayer);
      layers.add( // OSM attribution
          Container(padding: EdgeInsets.fromLTRB(0, 0, 0, Constants.screenHeight(context) / 2),
            child: const RichAttributionWidget(alignment: AttributionAlignment.bottomRight, attributions: [TextSourceAttribution('OpenStreetMap contributors',),],
            ),
          ));
    }
    lIndex = _layers.indexOf('Chart');
    if(_layersState[lIndex]) {
      layers.add(chartLayer);
    }
    lIndex = _layers.indexOf('Weather');
    if(_layersState[lIndex]) {
      layers.add(
          ValueListenableBuilder<int>(
              valueListenable: Storage().metar.change,
              builder: (context, value, _) {
                List<Weather> weather = Storage().metar.getAll();
                List<Metar> metars = weather.map((e) => e as Metar).toList();
                return MarkerClusterLayerWidget(  // too many metars, cluster them transparent
                    options: MarkerClusterLayerOptions(
                      markers: [
                        for(Metar m in metars)
                          Marker(point: m.coordinate,
                              child: JustTheTooltip(
                                content: Container(padding: const EdgeInsets.all(5), child:Text(m.toString())),
                                triggerMode: TooltipTriggerMode.tap,
                                waitDuration: const Duration(seconds: 1),
                                child: m.getIcon(),))
                      ],
                      builder: (context, markers) {
                        return Container(
                            decoration: const BoxDecoration(
                                color: Colors.transparent),
                            child: const Center()
                        );
                      },
                    )
                );
              }
          )
      );

      layers.add(
          ValueListenableBuilder<int>(
              valueListenable: Storage().airep.change,
              builder: (context, value, _) {
                List<Weather> weather = Storage().airep.getAll();
                List<Airep> airep = weather.map((e) => e as Airep).toList();
                return MarkerClusterLayerWidget(  // too many metars, cluster them transparent
                    options: MarkerClusterLayerOptions(
                      markers: [
                        for(Airep a in airep)
                          Marker(point: a.coordinates,
                              child:JustTheTooltip(
                                content: Container(padding: const EdgeInsets.all(5), child:Text(a.toString())),
                                triggerMode: TooltipTriggerMode.tap,
                                waitDuration: const Duration(seconds: 1),
                                child: const Icon(Icons.person, color: Colors.black,)))
                      ],
                      builder: (context, markers) {
                        return Container(
                            decoration: const BoxDecoration(
                                color: Colors.transparent),
                            child: const Center()
                        );
                      },
                    )
                );
              }
          )
      );

      layers.add(
          ValueListenableBuilder<int>(
              valueListenable: Storage().airSigmet.change,
              builder: (context, value, _) {
                List<Weather> weather = Storage().airSigmet.getAll();
                List<AirSigmet> airSigmet = weather.map((e) => e as AirSigmet).toList();
                return PolylineLayer(
                  polylines: [
                    // route
                    for(AirSigmet a in airSigmet)
                      if(a.showShape)
                        Polyline(
                            borderStrokeWidth: 1,
                            borderColor: Colors.white,
                            strokeWidth: 2,
                            points: a.coordinates,
                            color: a.getColor(),
                      ),
                  ],
                );
             }
          )
      );

      layers.add(
          ValueListenableBuilder<int>(
              valueListenable: Storage().airSigmet.change,
              builder: (context, value, _) {
                List<Weather> weather = Storage().airSigmet.getAll();
                List<AirSigmet> airSigmet = weather.map((e) => e as AirSigmet).toList();
                return MarkerLayer(
                  markers: [
                    // route
                    for(AirSigmet a in airSigmet)
                      Marker(
                        point: a.coordinates[0],
                        child: JustTheTooltip(
                          content: Container(
                            padding: const EdgeInsets.all(5),
                            child: Text(a.toString())
                          ),

                          waitDuration: const Duration(seconds: 1),
                          triggerMode: TooltipTriggerMode.tap,
                          child: GestureDetector(
                            onLongPress: () {
                              a.showShape = !a.showShape;
                              Storage().airSigmet.change.value++;
                            },
                            child:Icon(Icons.ac_unit_rounded,
                            color: a.getColor()
                          )
                          )
                        )
                      )
                  ],
                );

              }
          )
      );

      layers.add(
        // nexrad layer
        ValueListenableBuilder<int>(
          valueListenable: Storage().timeChange,
          builder: (context, value, _) {
            bool conus = true;
            if(_controller != null) {
              // show conus above zoom level 7
              conus = _controller!.camera.zoom < 7 ? true : false;
            }
            List<NexradImage> images = conus ? Storage().nexradCache.getNexradConus() : Storage().nexradCache.getNexrad();
            return OverlayImageLayer(
              overlayImages:
              images.map((e) {
                return OverlayImage(imageProvider: MemoryImage(e.getImage()!),
                    bounds: e.getBounds());
              }).toList(),
            );
          },
        ),
      );

    }

    lIndex = _layers.indexOf('TFR');
    if(_layersState[lIndex]) {
      layers.add( // route layer
        ValueListenableBuilder<int>(
          valueListenable: Storage().tfr.change,
          builder: (context, value, _) {
            List<Weather> weather = Storage().tfr.getAll();
            List<Tfr> tfrs = weather.map((e) => e as Tfr).toList();
            return PolylineLayer(
              polylines: [
                for (Tfr tfr in tfrs)
                  if(tfr.isRelevant())
                  // route
                    Polyline(
                      strokeWidth: 4,
                      points: tfr.coordinates, // red if in effect, orange if in future
                      color: tfr.isInEffect() ? Constants.tfrColor : Constants.tfrColorFuture,
                    ),
              ],
            );
          },
        ),
      );

      layers.add( // route layer
        ValueListenableBuilder<int>(
          valueListenable: Storage().tfr.change,
          builder: (context, value, _) {
            List<Weather> weather = Storage().tfr.getAll();
            List<Tfr> tfrs = weather.map((e) => e as Tfr).toList();

            return MarkerLayer(
              markers: [
                for (Tfr tfr in tfrs)
                  if(tfr.isRelevant())
                  // route
                    Marker(
                        point: tfr.coordinates[0],
                        child: JustTheTooltip(
                          content: Container(padding: const EdgeInsets.all(5), child:Text(tfr.toString())),
                          triggerMode: TooltipTriggerMode.tap,
                          waitDuration: const Duration(seconds: 1),
                          child: const Icon(Icons.warning_amber_sharp, color: Colors.black,),)
                    ),
              ],
            );
          },
        ),
      );

    }

    lIndex = _layers.indexOf('Plate');
    if(_layersState[lIndex]) {
      layers.add( // circle layer
        ValueListenableBuilder<int>(
            valueListenable: Storage().plateChange,
            builder: (context, value, _) {
              return OverlayImageLayer(
                overlayImages: [
                  if(Storage().imageBytesPlate != null &&
                      Storage().bottomRightPlate != null &&
                      Storage().topLeftPlate != null)
                    OverlayImage(
                      opacity: 0.9,
                      bounds: LatLngBounds(
                          Storage().topLeftPlate!,
                          Storage().bottomRightPlate!
                      ),
                      imageProvider: MemoryImage(Storage().imageBytesPlate!),
                    ),
                ],
              );
            }
        ),
      );
    }

    lIndex = _layers.indexOf('Traffic');
    if(_layersState[lIndex]) {
      layers.add(
        // traffic layer
        ValueListenableBuilder<int>(
          valueListenable: Storage().timeChange,
          builder: (context, value, _) {
            return MarkerLayer(
              markers:
              Storage().trafficCache.getTraffic().map((e) {
                return Marker( // our position and heading to destination
                    point: e.getCoordinates(),
                    child: JustTheTooltip(
                        content: Container(padding: const EdgeInsets.all(5), child:Text(e.toString())),
                        triggerMode: TooltipTriggerMode.tap,
                        waitDuration: const Duration(seconds: 1),
                        child: e.getIcon()));
              }).toList(),
            );
          },
        ),
      );
    }

    lIndex = _layers.indexOf('Tracks');
    if(_layersState[lIndex]) {
      layers.add( // tracks layer
        ValueListenableBuilder<Position>(
          valueListenable: Storage().gpsChange,
          builder: (context, value, _) {
            List<LatLng> path = Storage().tracks.getPoints();
            return PolylineLayer(
              polylines: [
                Polyline(
                  strokeWidth: 4,
                  points: path,
                  borderColor: Colors.white,
                  borderStrokeWidth: 1,
                  color: Constants.tracksColor,
                ),
              ],
            );
          },
        ),
      );
    }

    lIndex = _layers.indexOf('Nav');
    if(_layersState[lIndex]) {
      layers.add( // circle layer
        ValueListenableBuilder<Position>(
          valueListenable: Storage().gpsChange,
          builder: (context, value, _) {
            return CircleLayer(
              circles: [
                // 10 nm circle
                CircleMarker(
                  borderStrokeWidth: 3,
                  borderColor: Constants.distanceCircleColor,
                  color: Colors.transparent,
                  radius: Constants.nmToM(10), // 10 nm circle
                  useRadiusInMeter: true,
                  point: Gps.toLatLng(value),
                ),
                CircleMarker(
                  borderStrokeWidth: 3,
                  borderColor: Constants.distanceCircleColor,
                  color: Colors.transparent,
                  radius: Constants.nmToM(15), // 15 nm circle
                  useRadiusInMeter: true,
                  point: Gps.toLatLng(value),
                ),
                // speed marker
                CircleMarker(
                  borderStrokeWidth: 3,
                  borderColor: Constants.speedCircleColor,
                  color: Colors.transparent,
                  radius: value.speed * 60, // 1 minute speed
                  useRadiusInMeter: true,
                  point: Gps.toLatLng(value),
                ),
              ],
            );
          },
        ),
      );

      layers.add( // route layer
        ValueListenableBuilder<int>(
          valueListenable: Storage().route.change,
          builder: (context, value, _) {
            // we draw runways here.
            List<MapRunway> runways = [];
            if(Storage().route.getCurrentWaypoint() != null) {
              Destination destination = Storage().route.getCurrentWaypoint()!.destination;
              if(destination is AirportDestination) {
                runways = Airport.getRunwaysForMap(destination);
              }
            }
            return PolylineLayer(
              polylines: [
                // route
                Polyline(
                    borderStrokeWidth: 1,
                    borderColor: Constants.planBorderColor,
                    strokeWidth: 6,
                    points: Storage().route.getPathPassed(),
                    color: Constants.planPassedColor,
                ),
                Polyline(
                  borderStrokeWidth: 2,
                  borderColor: Constants.planBorderColor,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  points: Storage().route.getPathCurrent(),
                  color: Constants.planCurrentColor,
                ),
                Polyline(
                    borderStrokeWidth: 1,
                    borderColor: Constants.planBorderColor,
                    strokeWidth: 6,
                    points: Storage().route.getPathNext(),
                    color: Constants.planNextColor,
                ),
                for(MapRunway r in runways)
                  Polyline(
                    borderStrokeWidth: 1,
                    borderColor: Constants.planBorderColor,
                    strokeWidth: 4,
                    points: [r.start, r.end, r.endNotch],
                    color: Constants.runwayMapColor,
                  ),
              ],
            );
          },
        ),
      );

      layers.add( // route layer for runway numbers
        ValueListenableBuilder<int>(
          valueListenable: Storage().route.change,
          builder: (context, value, _) {
            // we draw runways here.
            List<MapRunway> runways = [];
            if(Storage().route.getCurrentWaypoint() != null) {
              Destination destination = Storage().route.getCurrentWaypoint()!.destination;
              if(destination is AirportDestination) {
                runways = Airport.getRunwaysForMap(destination);
              }
            }
            return MarkerLayer(
              markers: [
                for(MapRunway r in runways)
                  Marker(point: r.end,
                      width: 34,
                      child: Text(r.name, style: TextStyle(fontSize: 18, color: Constants.instrumentsNormalValueColor, backgroundColor: Constants.instrumentBackgroundColor),))
              ],
            );
          },
        ),
      );

      layers.add( // track layer
        ValueListenableBuilder<Position>(
          valueListenable: Storage().gpsChange,
          builder: (context, value, _) {
            // this place
            PlanRoute here = Storage().route;
            List<LatLng> path = here.getPathFromLocation(value);
            return PolylineLayer(
              polylines: [
                Polyline(
                  strokeWidth: 4,
                  points: path,
                  color: Constants.trackColor,
                ),
              ],
            );
          },
        ),
      );

      layers.add(
        // aircraft layer
        ValueListenableBuilder<Position>(
          valueListenable: Storage().gpsChange,
          builder: (context, value, _) {
            LatLng current = LatLng(value.latitude, value.longitude);

            return MarkerLayer(
              markers: [
                Marker( // our position and heading to destination
                    width: 32,
                    height: (Constants.screenWidth(context) +
                        Constants.screenHeight(context)) / 4,
                    point: current,
                    child: Transform.rotate(angle: value.heading * pi / 180,
                        child: CustomPaint(painter: Plane())
                    )
                ),
              ],
            );
          },
        ),
      );

    } // all nav layers

    // ruler, always present
    layers.add(
      ValueListenableBuilder<int>(
        valueListenable: _ruler.change,
        builder: (context, value, _) {
          int? distance;
          int? bearing;
          (distance, bearing) = _ruler.getDistanceBearing();
          LatLng? location0 = _ruler.getStart();
          LatLng? location1 = _ruler.getEnd();
          LatLng? middle = _ruler.getMiddle();
          return MarkerLayer(
            markers: [
              if (location0 != null)
                Marker(point: location0, child: const Icon(Icons.cancel_outlined, color: Colors.black,)),
              if (location1 != null)
                Marker(point: location1, child: const Icon(Icons.cancel_outlined, color: Colors.black,)),
              if (middle != null)
                Marker(point: middle, width: 128, child: Text("${distance.toString()}NM/${bearing.toString()}\u00b0", style: TextStyle(backgroundColor: Constants.instrumentBackgroundColor),))
            ],
          );
        },
      ),
    );

    FlutterMap map = FlutterMap(
      mapController: _controller,
      options: opts,
      children: layers,
    );

    // move with airplane but do not hold the map
    Storage().gpsChange.addListener(_listen);

    // for PFD, calculate heights
    double width;
    double height;
    if(Constants.isPortrait(context)) {
      height = Constants.screenHeight(context) / 3;
      width = height * 0.7;
    }
    else {
      height = Constants.screenHeight(context) * 3 / 5;
      width = height * 0.7;
    }
    Widget pfd = Positioned(
        child:Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width:width,
              height: height,
              child: ClipRRect(
                borderRadius: const BorderRadius.only( bottomRight: Radius.circular(40)),
                child:Opacity(opacity: 0.8,
                child:CustomPaint(
                  painter: PfdPainter(
                  height: height,
                  width: width,
                  repaint: Storage().timeChange) // repaint every second
                ))
              )
            )
        )
    );

    return Scaffold(
        endDrawer: Padding(padding: EdgeInsets.fromLTRB(0, Constants.screenHeight(context) / 8, 0, Constants.screenHeight(context) / 10),
            child: ValueListenableBuilder<bool>(
                valueListenable: Storage().warningChange,
                builder: (context, value, _) {
                  return WarningsWidget(gpsNotPermitted: Storage().gpsNotPermitted,
                    gpsDisabled: Storage().gpsDisabled, chartsMissing: Storage().chartsMissing,
                    dataExpired: Storage().dataExpired,
                    signed: Storage().settings.isSigned(),
                    gpsNoLock: Storage().gpsNoLock,);
                }
            )
        ),
        endDrawerEnableOpenDragGesture: false,
        body: Stack(
            children: [
              map, // map
              if(_layersState[_layers.indexOf('PFD')])
                pfd,
              // warn
              Positioned(
                child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
                        child: ValueListenableBuilder<bool>(
                            valueListenable: Storage().warningChange,
                            builder: (context, value, _) {
                              return WarningsButtonWidget(warning: value);
                            }
                        )
                    )
                ),
              ),
              Positioned(
                  child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(5, 5, 5, Constants.bottomPaddingSize(context)),
                          child: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: Constants.centerButtonBackgroundColor,
                              padding: const EdgeInsets.all(5.0),
                            ),
                            onPressed: () {
                              Position p = Storage().position;
                              LatLng l = LatLng(p.latitude, p.longitude);
                              if(_northUp) {
                                _controller == null ? {} : _controller!.moveAndRotate(l, _maxZoom.toDouble(), 0);// rotate to heading on center on track up
                              }
                              else {
                                _controller == null ? {} : _controller!.moveAndRotate(l, _maxZoom.toDouble(), -p.heading);
                              }
                            },
                            child: const Text("Center"),
                          )
                      )
                  )
              ),

              // menus
              Positioned(
                  child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(5, 5, 5, Constants.bottomPaddingSize(context)),
                          child: Row(children:[
                            // menu
                            TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: Constants.centerButtonBackgroundColor,
                              ),
                              onPressed: () {
                                Scaffold.of(context).openDrawer();
                              },
                              child: const Text("Menu"),
                            ),

                            // north up
                            IconButton(
                                onPressed: () {
                                  setState(() {
                                    _northUp = _northUp ? false : true;
                                  });
                                  Storage().settings.setNorthUp(_northUp); // save
                                },
                                icon: ValueListenableBuilder<Position>(
                                    valueListenable: Storage().gpsChange,
                                    builder: (context, value, _) {
                                      return CircleAvatar( // in track up, rotate icon
                                          backgroundColor: Constants.dropDownButtonBackgroundColor,
                                          child: _northUp ? Icon(MdiIcons.navigation) :
                                          Transform.rotate(
                                              angle: value.heading * pi / 180,
                                              child: Icon(MdiIcons.arrowUpThinCircleOutline)));
                                    }
                                )),

                          ])
                      )
                  )
              ),

              Positioned(
                  child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(5, 5, 5, Constants.bottomPaddingSize(context)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end, children:[
                              Row(mainAxisAlignment: MainAxisAlignment.end,
                                children:[
                                  IconButton(onPressed: () {setState(() {
                                    if(_ruler.isMeasuring()) {
                                      _ruler.init();
                                    }
                                    else {
                                      _ruler.init();
                                      _ruler.startMeasure();
                                    }
                                  });}, icon: CircleAvatar(backgroundColor: _ruler.color(), child: Icon(MdiIcons.mathCompass))),
                                  // switch layers on off
                                  PopupMenuButton( // airport selection
                                    icon: CircleAvatar(backgroundColor: Constants.dropDownButtonBackgroundColor, child: const Icon(Icons.layers)),
                                    initialValue: _layers[0],
                                    itemBuilder: (BuildContext context) =>
                                        List.generate(_layers.length, (int index) => PopupMenuItem(
                                          child: StatefulBuilder(
                                            builder: (context1, setState1) =>
                                                ListTile(
                                                  dense: true,
                                                  title: Text(_layers[index]),
                                                  subtitle: _layersState[index] ? const Text("Layer is On") : const Text("Layer is Off"),
                                                  leading: Switch(
                                                    value: _layersState[index],
                                                    onChanged: (bool value) {
                                                      setState1(() {
                                                        _layersState[index] = value;
                                                        if(_layers[index] == "Tracks") {
                                                          if(value == false) {
                                                            // save tracks on turning them off then show user where to get them
                                                            Storage().settings.setDocumentPage(DocumentsScreen.userDocuments);
                                                            Storage().tracks.saveKml().then((value) {
                                                              Navigator.pushNamed(context, '/documents');
                                                            });
                                                          }
                                                          else {
                                                            Storage().tracks.reset(); //on turning on, start fresh
                                                          }
                                                        }
                                                      });
                                                      // now save to settings
                                                      Storage().settings.setLayersState(_layersState);
                                                      setState(() {
                                                        _layersState[index] = value; // this is the state for the map
                                                      });
                                                      // Turn audible alerts off and on depending on traffic layer
                                                      Storage().settings.setAudibleAlertsEnabled(_layersState[Storage().settings.getLayers().indexOf("Traffic")]);                                                
                                                    },
                                                  ),
                                                ),
                                          ),)
                                        ),
                                    ),
                                  ]
                                ),
                                // chart select
                                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  DropdownButtonHideUnderline(
                                    child:DropdownButton2<String>(
                                      buttonStyleData: ButtonStyleData(
                                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Constants.dropDownButtonBackgroundColor),
                                      ),
                                      dropdownStyleData: DropdownStyleData(
                                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      isExpanded: false,
                                      value: _type,
                                      items: _charts.map((String item) {
                                        return DropdownMenuItem<String>(
                                            value: item,
                                            child: Text(item, style: TextStyle(fontSize: Constants.dropDownButtonFontSize))
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          Storage().settings.setChartType(value ?? _charts[0]);
                                          _type = Storage().settings.getChartType();
                                        });
                                      },
                                    )
                                )
                              ]),
                          ])
                      )
                  )
              )
            ]
        )
    );
  }
// implements a drawing screen with a center reset button.
}

class Plane extends CustomPainter {


  final _paintCenter = Paint()
    ..style = PaintingStyle.fill
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.square
    ..color = Constants.planeColor;

  @override
  void paint(Canvas canvas, Size size) {

    // draw plane
    canvas.drawLine(Offset(size.width / 2, size.height / 2 + 16), Offset(size.width / 2, size.height / 2 + 16), _paintCenter);
    canvas.drawLine(Offset(size.width / 2, size.height / 2 + 8), Offset(size.width / 2, 0), _paintCenter);
    canvas.drawLine(Offset(size.width / 2 - 16, size.height / 2), Offset(size.width / 2 + 16, size.height / 2), _paintCenter);
  }

  @override
  bool shouldRepaint(Plane oldDelegate) => false;
}

// custom tile provider
class ChartTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    File f = File(getTileUrl(coordinates, options));
    if(f.existsSync()) {
      // get rid of annoying tile name error problem by providing a transparent tile
      return FileImage(File(getTileUrl(coordinates, options)));
    }
    return FileImage(File(join(Storage().dataDir, "256.png")));
  }
}

// for scale measurement
class Ruler {

  int? _pointer0id;
  int? _pointer1id;
  LatLng? _ll0;
  LatLng? _ll1;
  bool _measuring = false;
  final change = ValueNotifier<int>(0);
  final GeoCalculations geo = GeoCalculations();

  void init() {
    _pointer0id = null;
    _ll0 = null;
    _pointer1id = null;
    _ll1 = null;
    _measuring = false;
    change.value++;
  }

  void setPointer(int id, LatLng position) {
    if(!_measuring) {
      return;
    }
    if(null == _pointer0id)  {
      _pointer0id = id;
      _ll0 = position;
      change.value++;

    }
    else if(null == _pointer1id)  {
      _pointer1id = id;
      _ll1 = position;
      change.value++;
    }
  }

  LatLng? getStart() {
    return _ll0;
  }

  LatLng? getEnd() {
    return _ll1;
  }

  LatLng? getMiddle() {
    if(_ll1 != null && _ll0 != null) {
      return LatLng((_ll0!.latitude + _ll1!.latitude) / 2, (_ll0!.longitude + _ll1!.longitude) / 2);
    }
    return null;
  }

  (int?, int?) getDistanceBearing() {
    if(_ll1 != null && _ll0 != null) {
      double variation = geo.getVariation(getMiddle()!);
      double bearing = GeoCalculations.getMagneticHeading(geo.calculateBearing(_ll0!, _ll1!), variation);
      return (geo.calculateDistance(_ll0!, _ll1!).round(), bearing.round());
    }
    return (null, null);
  }

  Color color() {
    if(_measuring) {
      return Colors.blueAccent;
    }
    return Constants.dropDownButtonBackgroundColor;
  }

  void startMeasure() {
    _measuring = true;
  }

  bool isMeasuring() {
    return _measuring;
  }

}
