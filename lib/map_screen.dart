import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/destination/airport.dart';
import 'package:avaremp/documents_screen.dart';
import 'package:avaremp/gdl90/nexrad_cache.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/instrument_list.dart';
import 'package:avaremp/pfd_painter.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/airep.dart';
import 'package:avaremp/weather/airsigmet.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/weather/tfr.dart';
import 'package:avaremp/warnings_widget.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'chart.dart';
import 'constants.dart';
import 'package:avaremp/destination/destination.dart';
import 'download_screen.dart';
import 'gps.dart';
import 'weather/metar.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<StatefulWidget> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {

  static const double iconRadius = 18;

  StreamController<void>? mapReset; // to reset the radar map
  void resetRadar() {
    if(mapReset != null) {
      mapReset!.add(null);
    }
    for(int i = 0; i < Storage().mesonetCache.length; i++) {
      Storage().mesonetCache[i].clean(); // clean mesonet cache
    }
  }

  final List<String> _charts = DownloadScreenState.getCategories();
  LatLng? _previousPosition;
  bool _interacting = false;
  bool _rubberBanding = false;
  final Ruler _ruler = Ruler();
  String _type = Storage().settings.getChartType();
  int _maxZoom = ChartCategory.chartTypeToZoom(Storage().settings.getChartType());
  MapController? _controller;
  // get layers and states from settings
  final List<String> _layers = Storage().settings.getLayers();
  final List<double> _layersOpacity = Storage().settings.getLayersOpacity();
  final int disableClusteringAtZoom = 10;
  final int maxClusterRadius = 160;
  bool _northUp = Storage().settings.getNorthUp();
  final GeoCalculations calculations = GeoCalculations();
  final ValueNotifier<(List<LatLng>, List<String>)> tapeNotifier = ValueNotifier<(List<LatLng>, List<String>)>(([],[]));

  static Future<void> showDestination(BuildContext context, List<Destination> destinations) async {
    await Navigator.pushNamed(context, "/popup", arguments: destinations);
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

  // for measuring tape
  void _handleEvent(MapEvent mapEvent) {
    if(_controller != null) {
      LatLng center = Gps.toLatLng(Storage().gpsChange.value);
      LatLng topCenter = _controller!.camera.pointToLatLng(Point(Constants.screenWidth(context) / 2, Constants.screenHeightForInstruments(context) + iconRadius));
      String centralDistance = calculations.calculateDistance(center, topCenter).round().toString();
      LatLng topLeft = _controller!.camera.pointToLatLng(const Point(iconRadius, 0));
      LatLng bottomLeft = _controller!.camera.pointToLatLng(Point(iconRadius, Constants.screenHeight(context)));
      double ticksInLatitude = ((topLeft.latitude - bottomLeft.latitude)).round() / 6;
      if(ticksInLatitude < 0.1) {
        ticksInLatitude = 0.1; // avoid busy loop
      }
      // run a loop to find markers
      List<LatLng> llVertical = [];
      List<String> distanceVertical = [];
      for (double latitude = center.latitude; latitude < topLeft.latitude; latitude += ticksInLatitude) {
        if (latitude > topLeft.latitude || latitude < bottomLeft.latitude) {
          continue; // outside of view area
        }
        double avgLon = (bottomLeft.longitude + topLeft.longitude) / 2;
        LatLng ll = LatLng(latitude, avgLon);
        double d = calculations.calculateDistance(LatLng(center.latitude, avgLon), ll);
        distanceVertical.add(d.round().toString());
        llVertical.add(ll);
      }
      for (double latitude = center.latitude; latitude > bottomLeft.latitude; latitude -= ticksInLatitude) {
        if (latitude > topLeft.latitude || latitude < bottomLeft.latitude) {
          continue; // outside of view area
        }
        double avgLon = (bottomLeft.longitude + topLeft.longitude) / 2;
        LatLng ll = LatLng(latitude, avgLon);
        double d = calculations.calculateDistance(LatLng(center.latitude, avgLon), ll);
        distanceVertical.add(d.round().toString());
        llVertical.add(ll);
      }
      tapeNotifier.value = (llVertical + [topCenter], distanceVertical + [centralDistance]);
    }
  }

  // this pans camera on move
  void _listen() {
    final LatLng cur = Gps.toLatLng(Storage().position);
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
      catch (e) {} // adding to lat lon is dangerous
    }

    _previousPosition = Gps.toLatLng(Storage().position);
  }

  @override
  Widget build(BuildContext context) {
    double opacity = 1.0;
    if (mapReset != null) {
      mapReset!.close();
    }
    mapReset = StreamController();

    TileLayer osmLayer = TileLayer(
      urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
      tileProvider: CachedTileProvider(
        // maxStale keeps the tile cached for the given Duration and
        // tries to revalidate the next time it gets requested
          maxStale: const Duration(days: 30),
          store: Storage().osmCache),
    );

    TileLayer openaipLayer = TileLayer(
        maxNativeZoom: 16,
        urlTemplate: "https://api.tiles.openaip.net/api/data/openaip/{z}/{x}/{y}.png?apiKey=@@___openaip_client_id__@@",
        tileProvider: CachedTileProvider(store: Storage().openaipCache));

    TileLayer topoLayer = TileLayer(
      maxNativeZoom: 16,
      urlTemplate: "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/WMTS/tile/1.0.0/USGSTopo/default/default028mm/{z}/{y}/{x}.png",
      tileProvider: CachedTileProvider(
        // maxStale keeps the tile cached for the given Duration and
        // tries to revalidate the next time it gets requested
          maxStale: const Duration(days: 30),
          store: Storage().topoCache),
    );

    String index = ChartCategory.chartTypeToIndex(_type);
    _maxZoom = ChartCategory.chartTypeToZoom(_type);

    // 5 images for animation
    List<TileLayer> nexradLayer = List.generate(5, (int index) {
      List<String> mesonets = [
        "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m40m/{z}/{x}/{y}.png",
        "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m30m/{z}/{x}/{y}.png",
        "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m20m/{z}/{x}/{y}.png",
        "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m10m/{z}/{x}/{y}.png",
        "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png"
      ];
      return TileLayer(
        maxNativeZoom: 5,
        reset: mapReset!.stream,
        urlTemplate: mesonets[index],
        tileProvider: CachedTileProvider(
          // maxStale keeps the tile cached for the given Duration and
          // tries to revalidate the next time it gets requested
            maxStale: const Duration(minutes: 1),
            store: Storage().mesonetCache[index]),
      );
    });

    //add layers
    List<Widget> layers = [];

    TileLayer chartLayer = TileLayer(
        tms: true,
        maxNativeZoom: _maxZoom,
        tileProvider: ChartTileProvider(),
        urlTemplate: "${Storage().dataDir}/tiles/$index/{z}/{x}/{y}.webp");

    // start from known location
    MapOptions opts = MapOptions(
      initialCenter: LatLng(Storage().settings.getCenterLatitude(),
          Storage().settings.getCenterLongitude()),
      initialZoom: Storage().settings.getZoom(),
      minZoom: 2,
      // this is less crazy
      maxZoom: 20,
      // max for USGS
      interactionOptions: InteractionOptions(flags: _northUp
          ? InteractiveFlag.all & ~InteractiveFlag.rotate
          : InteractiveFlag.all),
      // no rotation in track up
      initialRotation: Storage().settings.getRotation(),
      backgroundColor: Constants.mapBackgroundColor,
      onLongPress: (tap, point) async {
        List<Destination> items = await MainDatabaseHelper.db.findNear(point);
        setState(() {
          showDestination(this.context, items);
        });
      },
      onPointerDown: (PointerDownEvent event,
          position) { // calculate down pointers here
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
        _handleEvent(mapEvent);
      },
    );

    int lIndex = _layers.indexOf('OSM');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(Opacity(opacity: opacity, child: osmLayer));
      layers.add( // OSM attribution
          Container(padding: EdgeInsets.fromLTRB(
              0, 0, 0, Constants.screenHeight(context) / 2),
            child: const RichAttributionWidget(
              alignment: AttributionAlignment.bottomRight,
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors',),
              ],
            ),
          ));
    }
    lIndex = _layers.indexOf('Topo');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(Opacity(opacity: opacity, child: topoLayer));
    }
    lIndex = _layers.indexOf('OpenAIP');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(Opacity(opacity: opacity, child: openaipLayer));
      layers.add(
          Container(padding: EdgeInsets.fromLTRB(
              0, 0, 0, Constants.screenHeight(context) / 2),
            child: const RichAttributionWidget(
              alignment: AttributionAlignment.bottomRight,
              attributions: [TextSourceAttribution('OpenAIP contributors',),],
            ),
          ));
    }
    lIndex = _layers.indexOf('Chart');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(Opacity(opacity: opacity, child: chartLayer));
    }

    // Custom shapes
    lIndex = _layers.indexOf('GeoJSON');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
        valueListenable: Storage().geoParser.change,
        builder: (context, value, _) {
          return PolygonLayer(polygons: Storage().geoParser.polygons);
        })
      ));

      layers.add(Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
          valueListenable: Storage().geoParser.change,
          builder: (context, value, _) {
            return MarkerClusterLayerWidget( //cluster them transparent
                options: MarkerClusterLayerOptions(
                  markers: Storage().geoParser.markers,
                  maxClusterRadius: 45,
                  disableClusteringAtZoom: 15,
                  size: const Size(40, 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(50),
                  maxZoom: 20,
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.blue.withAlpha(128)),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                )
            );
          })
      ));
    }

    int nexradLength = nexradLayer.length;
    lIndex = _layers.indexOf('Radar');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(
          Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
              valueListenable: Storage().timeChange,
              builder: (context, value, _) {
                if(value % 300 == 0) {
                  // download new nexrad every 5 minutes
                  resetRadar();
                }
                int index = value % (nexradLength * 2);
                if(index > nexradLength - 1) {
                  index = nexradLength - 1; // give 2 times the time for latest to stay on
                }
                return nexradLayer[index]; // animate every 3 seconds
          })
      ));

      // nexrad
      layers.add(// nexrad slider
          Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
              valueListenable: Storage().timeChange,
              builder: (context, value, _) {
                int index = value % (nexradLength * 2);
                if(index > nexradLength - 1) {
                  index = nexradLength - 1; // give 2 times the time for latest to stay on
                }
                return Container(height: 30, width: Constants.screenWidth(context) / 3, padding: EdgeInsets.fromLTRB(10, Constants.screenHeightForInstruments(context) + 20, 0, 0),
                  child: Slider(value: index / (nexradLength - 1), onChanged: (double value) {  },),
              );
          })
      ));
    }

    lIndex = _layers.indexOf('Weather');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(
          Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
              valueListenable: Storage().metar.change,
              builder: (context, value, _) {
                List<Weather> weather = Storage().metar.getAll();
                List<Metar> metars = weather.map((e) => e as Metar).toList();
                return MarkerClusterLayerWidget(  // too many metars, cluster them transparent
                    options: MarkerClusterLayerOptions(
                      disableClusteringAtZoom: disableClusteringAtZoom,
                      maxClusterRadius: maxClusterRadius,
                      markers: [
                        for(Metar m in metars)
                          Marker(point: m.coordinate,
                              alignment: Alignment.topRight,
                              child: Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180, child: JustTheTooltip(
                                content: Container(padding: const EdgeInsets.all(5), child:Text(m.toString())),
                                triggerMode: TooltipTriggerMode.tap,
                                waitDuration: const Duration(seconds: 1),
                                child: m.getIcon(),)))
                      ],
                      builder: (context, markers) {
                        return Container(color: Colors.transparent,);
                      },
                    )
                );
              }
          )
      ));

      layers.add(
          Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
              valueListenable: Storage().taf.change,
              builder: (context, value, _) {
                List<Weather> weather = Storage().taf.getAll();
                List<Taf> tafs = weather.map((e) => e as Taf).toList();
                return MarkerClusterLayerWidget(  // too many tafs, cluster them transparent
                    options: MarkerClusterLayerOptions(
                      disableClusteringAtZoom: disableClusteringAtZoom,
                      maxClusterRadius: maxClusterRadius,
                      markers: [
                        for(Taf t in tafs)
                          Marker(point: t.coordinate,
                              width: 32,
                              height: 32,
                              alignment: Alignment.bottomRight,
                              child: Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180, child: JustTheTooltip(
                                content: Container(padding: const EdgeInsets.all(5), child:Text(t.toString())),
                                triggerMode: TooltipTriggerMode.tap,
                                waitDuration: const Duration(seconds: 1),
                                child: t.getIcon(),)))
                      ],
                      builder: (context, markers) {
                        return Container(color: Colors.transparent,);
                      },
                    )
                );
              }
          )
      ));

      layers.add(
          Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
              valueListenable: Storage().airep.change,
              builder: (context, value, _) {
                List<Weather> weather = Storage().airep.getAll();
                List<Airep> airep = weather.map((e) => e as Airep).toList();
                return MarkerClusterLayerWidget(  // too many metars, cluster them transparent
                    options: MarkerClusterLayerOptions(
                      disableClusteringAtZoom: disableClusteringAtZoom,
                      maxClusterRadius: maxClusterRadius,
                      markers: [
                        for(Airep a in airep)
                          Marker(point: a.coordinates,
                              alignment: Alignment.bottomLeft,
                              child: Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180, child: JustTheTooltip(
                                content: Container(padding: const EdgeInsets.all(5), child:Text(a.toString())),
                                triggerMode: TooltipTriggerMode.tap,
                                waitDuration: const Duration(seconds: 1),
                                child: const Icon(Icons.person, color: Colors.black,))))
                      ],
                      builder: (context, markers) {
                        return Container(color: Colors.transparent,);
                      },
                    )
                );
              }
          )
      ));

      layers.add(
          Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
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
      ));

      layers.add(
          Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
              valueListenable: Storage().airSigmet.change,
              builder: (context, value, _) {
                List<Weather> weather = Storage().airSigmet.getAll();
                List<AirSigmet> airSigmet = weather.map((e) => e as AirSigmet).toList();

                return MarkerClusterLayerWidget(  // too many metars, cluster them transparent
                  options: MarkerClusterLayerOptions(
                    disableClusteringAtZoom: disableClusteringAtZoom,
                    maxClusterRadius: maxClusterRadius,
                    markers: [
                      // route
                      for(AirSigmet a in airSigmet)
                        Marker(
                          point: a.coordinates[0],
                          child: Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180, child: JustTheTooltip(
                            content: Container(
                              padding: const EdgeInsets.all(5),
                              child: Text("${a.toString()}\n** Long press to show/hide the covered area **")
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
                        ))
                    ],
                    builder: (context, markers) {
                      return Container(color: Colors.transparent,);
                    },
                  )
                );
              }
          )
      ));

      layers.add(
        // nexrad layer
        Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
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
      ));
    }

    lIndex = _layers.indexOf('TFR');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add( // route layer
        Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
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
      ));

      layers.add( // route layer
        Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
          valueListenable: Storage().tfr.change,
          builder: (context, value, _) {
            List<Weather> weather = Storage().tfr.getAll();
            List<Tfr> tfrs = weather.map((e) => e as Tfr).toList();

            return MarkerClusterLayerWidget(  // too many metars, cluster them transparent
                options: MarkerClusterLayerOptions(
                  disableClusteringAtZoom: disableClusteringAtZoom,
                  maxClusterRadius: maxClusterRadius,
                  markers: [
                    for (Tfr tfr in tfrs)
                      if(tfr.isRelevant())
                        Marker(
                            point: tfr.coordinates[tfr.getLabelCoordinate()],
                            child: Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180, child: JustTheTooltip(
                              content: Container(padding: const EdgeInsets.all(5), child:Text(tfr.toString())),
                              triggerMode: TooltipTriggerMode.tap,
                              waitDuration: const Duration(seconds: 1),
                              child: Icon(MdiIcons.clockAlert, color: Colors.black,),))
                        ),
                  ],
              builder: (context, markers) {
                return Container(color: Colors.transparent,);
              },
            ));
          },
        ),
      ));
    }

    lIndex = _layers.indexOf('Plate');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add( // circle layer
        Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
            valueListenable: Storage().plateChange,
            builder: (context, value, _) {
              return OverlayImageLayer(
                overlayImages: [
                  if(Storage().imageBytesPlate != null &&
                      Storage().bottomRightPlate != null &&
                      Storage().topLeftPlate != null)
                    OverlayImage(
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
      ));
    }

    lIndex = _layers.indexOf('Traffic');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(
        // traffic layer
        Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
          valueListenable: Storage().timeChange,
          builder: (context, value, _) {
            return MarkerLayer(
              markers:
              Storage().trafficCache.getTraffic().map((e) {
                return Marker( // our position and heading to destination
                  point: e.getCoordinates(),
                  child: GestureDetector(child:Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180,
                    child: JustTheTooltip(
                      content: Container(padding: const EdgeInsets.all(5), child:Text(e.toString())),
                      triggerMode: TooltipTriggerMode.tap,
                      waitDuration: const Duration(seconds: 1),
                      child: e.getIcon(_northUp, Storage().settings.isAudibleAlertsEnabled())
                    )
                  ),
                  onLongPress: () {
                    setState(() { // disable/enable audible alerts
                      Storage().settings.setAudibleAlertsEnabled(!Storage().settings.isAudibleAlertsEnabled());
                    });
                  },
                )); // undo the above rotation
              }).toList(),
            );
          },
        ),
      ));
    }

    lIndex = _layers.indexOf('Tracks');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add( // tracks layer
        Opacity(opacity: opacity, child: ValueListenableBuilder<Position>(
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
      ));
    }

    lIndex = _layers.indexOf('Circles');
    opacity = _layersOpacity[lIndex];
    if(opacity > 0) {
        layers.add( // tape
          Opacity(opacity: opacity, child: ValueListenableBuilder<(List<LatLng>, List<String>)>(
            valueListenable: tapeNotifier,
            builder: (context, value, _) {
              return MarkerLayer(
                  markers: [
                    for(int index = 0; index < value.$1.length; index++)
                      Marker(point: value.$1[index], width: 32, alignment: Alignment.center,
                        child: Container(width: 32,
                          decoration: BoxDecoration(borderRadius: const BorderRadius.all(Radius.circular(12)), color: Theme.of(context).cardColor.withOpacity(0.6)),
                            child: SizedBox(width: 32, child: FittedBox(
                              child: Padding(padding: const EdgeInsets.all(3),
                                child:Text(value.$2[index], style: const TextStyle(fontWeight: FontWeight.w600),)))
                        ))
                      ),
                  ]
              );
            },
          ),
        ));

        layers.add( // circle layer
          Opacity(opacity: opacity, child: ValueListenableBuilder<Position>(
            valueListenable: Storage().gpsChange,
            builder: (context, value, _) {
              return CircleLayer(
                circles: [
                  // 10 nm circle
                  CircleMarker(
                    borderStrokeWidth: 3,
                    borderColor: Constants.distanceCircleColor,
                    color: Colors.transparent,
                    radius: Storage().units.toM * 10,
                    // 10 nm circle
                    useRadiusInMeter: true,
                    point: Gps.toLatLng(value),
                  ),
                  CircleMarker(
                    borderStrokeWidth: 3,
                    borderColor: Constants.distanceCircleColor,
                    color: Colors.transparent,
                    radius: Storage().units.toM * 5,
                    // 15 nm circle
                    useRadiusInMeter: true,
                    point: Gps.toLatLng(value),
                  ),
                  CircleMarker(
                    borderStrokeWidth: 3,
                    borderColor: Constants.distanceCircleColor,
                    color: Colors.transparent,
                    radius: Storage().units.toM * 2,
                    // 10 nm circle
                    useRadiusInMeter: true,
                    point: Gps.toLatLng(value),
                  ),
                  // speed marker
                  CircleMarker(
                    borderStrokeWidth: 3,
                    borderColor: Constants.speedCircleColor,
                    color: Colors.transparent,
                    radius: value.speed * 60,
                    // 1 minute speed
                    useRadiusInMeter: true,
                    point: Gps.toLatLng(value),
                  ),
                ],
              );
            },
          ),
        ));

        layers.add( // circle layer labels
          Opacity(opacity: opacity, child: ValueListenableBuilder<Position>(
            valueListenable: Storage().gpsChange,
            builder: (context, value, _) {
              return MarkerLayer(
                markers: [
                  Marker(point: GeoCalculations().calculateOffset(
                      Gps.toLatLng(value), 10, 330),
                      child: Transform.rotate(
                          angle: _northUp ? 0 : Storage().position.heading * pi /
                              180, child:
                      CircleAvatar(
                          backgroundColor: Constants.bottomNavBarBackgroundColor,
                          child: const Text("10", style: TextStyle(fontSize: 14,
                            color: Colors.white,),)))),
                  Marker(point: GeoCalculations().calculateOffset(
                      Gps.toLatLng(value), 5, 330),
                      child: Transform.rotate(
                          angle: _northUp ? 0 : Storage().position.heading * pi /
                              180, child:
                      CircleAvatar(
                          backgroundColor: Constants.bottomNavBarBackgroundColor,
                          child: const Text("5", style: TextStyle(fontSize: 14,
                            color: Colors.white,),)))),
                  Marker(point: GeoCalculations().calculateOffset(
                      Gps.toLatLng(value), 2, 330),
                      child: Transform.rotate(
                          angle: _northUp ? 0 : Storage().position.heading * pi /
                              180, child:
                      CircleAvatar(
                          backgroundColor: Constants.bottomNavBarBackgroundColor,
                          child: const Text("2", style: TextStyle(fontSize: 14,
                            color: Colors.white,),)))),
                ],
              );
            },
          ),
        ));
      }

      lIndex = _layers.indexOf('Obstacles');
      opacity = _layersOpacity[lIndex];
      if (opacity > 0) {
        //obstacles
        layers.add(
            Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
                valueListenable: Storage().timeChange,
                builder: (context, value, _) {
                  return MarkerLayer(markers: [
                    for(LatLng ll in Storage().area.obstacles)
                      Marker(point: ll,
                        child: Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180,
                          child: const Icon(Icons.square, color: Colors.red, size: 20,)))
                  ]);
                })
            )
        );
      }

    lIndex = _layers.indexOf('Nav');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
        layers.add( // route layer
          Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
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
      ));

      layers.add( // route layer for runway numbers
        Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
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
                      child: Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180, child: CircleAvatar(backgroundColor: r.best ? Colors.green : Colors.purple, child:Text(r.name, style: const TextStyle(fontSize: 14, color: Colors.white, ),)))),
              ],
            );
          },
        ),
      ));

      layers.add( // track layer
        Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
          valueListenable: Storage().timeChange,
          builder: (context, value, _) {
            // this place
            PlanRoute here = Storage().route;
            List<LatLng> path = here.getPathFromLocation(Storage().position);
            return PolylineLayer(
              polylines: [
                Polyline(
                  strokeWidth: 4,
                  points: path,
                  borderStrokeWidth: 2,
                  borderColor: Constants.planBorderColor,
                  color: Constants.trackColor,
                ),
              ],
            );
          },
        ),
      ));

      layers.add( // route layer for waypoints
        Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
          valueListenable: Storage().route.change,
          builder: (context, value, _) {
            List<Destination> destinations = Storage().route.getAllDestinations();
            return MarkerLayer(
              markers: [
                for(int index = 0; index < destinations.length; index++) // plan route
                  Marker(alignment: Alignment.center, point: destinations[index].coordinate,
                    child: Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180,
                      child: CircleAvatar(backgroundColor: Constants.waypointBackgroundColor,
                        child: (Storage().settings.isRubberBanding()) ? // when rubber banding, show red/white
                          GestureDetector(
                              onLongPressMoveUpdate: (details) {
                                if(!Storage().settings.isRubberBanding()) {
                                  return;
                                }
                                if(null != _controller && _rubberBanding) { // start rubber banding
                                  LatLng l = _controller!.camera.pointToLatLng(Point(details.globalPosition.dx, details.globalPosition.dy));
                                  Storage().route.replaceDestination(index, l);
                                }
                             },
                              onLongPressCancel: () {
                                _rubberBanding = false;
                              },
                              onLongPressStart: (details) {
                                if(!Storage().settings.isRubberBanding()) {
                                  return;
                                }
                                _rubberBanding = true;
                              },
                              onLongPressEnd: (details) {
                                if(!Storage().settings.isRubberBanding()) {
                                  return;
                                }
                                _rubberBanding = false;
                                if(null != _controller) { // end rubber banding
                                  LatLng l = _controller!.camera.pointToLatLng(Point(details.globalPosition.dx, details.globalPosition.dy));
                                  Storage().route.replaceDestinationFromDb(index, l);
                                }
                              },
                              child: DestinationFactory.getIcon(destinations[index].type, _rubberBanding ? Colors.red : Colors.white)) :
                          GestureDetector(
                              onTap: () {
                                setState(() {
                                  Storage().route.setCurrentWaypointFromDestinationIndex(index);
                                });
                              },
                              child: DestinationFactory.getIcon(destinations[index].type, _rubberBanding ? Colors.red : Colors.white))
                      )
                    )
                  ),
                for(int index = 0; index < destinations.length; index++) // plan route
                  Marker(alignment: Alignment.bottomRight, point: destinations[index].coordinate, width: 64,
                      child: Transform.rotate(angle: _northUp ? 0 : Storage().position.heading * pi / 180,
                        child: (Storage().settings.isRubberBanding()) ? // when rubber banding, show red/white
                          GestureDetector(
                              onLongPressMoveUpdate: (details) {
                                if(!Storage().settings.isRubberBanding()) {
                                  return;
                                }
                                if(null != _controller && _rubberBanding) { // start rubber banding
                                  LatLng l = _controller!.camera.pointToLatLng(Point(details.globalPosition.dx, details.globalPosition.dy));
                                  Storage().route.replaceDestination(index, l);
                                }
                              },
                              onLongPressCancel: () {
                                if(!Storage().settings.isRubberBanding()) {
                                  return;
                                }
                                _rubberBanding = false;
                              },
                              onLongPressStart: (details) {
                                if(!Storage().settings.isRubberBanding()) {
                                  return;
                                }
                                _rubberBanding = true;
                              },
                              onLongPressEnd: (details) {
                                if(!Storage().settings.isRubberBanding()) {
                                  return;
                                }
                                _rubberBanding = false;
                                if(null != _controller) { // end rubber banding
                                  LatLng l = _controller!.camera.pointToLatLng(Point(details.globalPosition.dx, details.globalPosition.dy));
                                  Storage().route.replaceDestinationFromDb(index, l);
                                }
                              },
                              onTap: () {
                                setState(() {
                                  Storage().route.setCurrentWaypointFromDestinationIndex(index);
                                });
                            },
                            // do not clobber screen with sexagesimal
                            child: AutoSizeText(destinations[index].type != Destination.typeGps ? destinations[index].locationID : destinations[index].facilityName, style: TextStyle(color: Colors.white, backgroundColor: _rubberBanding ? Colors.red : Constants.planCurrentColor.withAlpha(160)), minFontSize: 1,)) :
                        GestureDetector(
                            onTap: () {
                              setState(() {
                                Storage().route.setCurrentWaypointFromDestinationIndex(index);
                              });
                            },
                            // do not clobber screen with sexagesimal
                            child: AutoSizeText(destinations[index].type != Destination.typeGps ? destinations[index].locationID : destinations[index].facilityName, style: TextStyle(color: Colors.white, backgroundColor: _rubberBanding ? Colors.red : Constants.planCurrentColor.withAlpha(160)), minFontSize: 1,))
                      )
                  )
              ],
            );
          },
        ),
      ));

      layers.add(
        // aircraft layer
        Opacity(opacity: opacity, child: ValueListenableBuilder<Position>(
          valueListenable: Storage().gpsChange,
          builder: (context, value, _) {
            LatLng current = LatLng(value.latitude, value.longitude);
            double? ws;
            double? wd;
            (wd, ws) = Storage().area.getWind(GeoCalculations.convertAltitude(value.altitude));
            return MarkerLayer(
              markers: [
                Marker( // our position and heading to destination
                    width: 48,
                    height: (Constants.screenWidth(context) +
                        Constants.screenHeight(context)) / 2,
                    point: current,
                    child: Transform.rotate(angle: value.heading * pi / 180,
                        child: CustomPaint(painter: Plane())
                    )
                ),
                if(wd != null && ws != null)
                  Marker( // our position and heading to destination
                      width: 64,
                      height: 64,
                      point: current,
                      child: CustomPaint(painter: WindBarbPainter(ws, wd))
                  ),
                Marker( // variation
                    width: 48,
                    height: 48,
                    point: current,
                    child: CustomPaint(painter: NorthPainter(Storage().area.variation))
                ),
              ],
            );
          },
        ),
      ));

    } // all nav layers

    // ruler, always present
    layers.add(
      Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
        valueListenable: _ruler.change,
        builder: (context, value, _) {
          List<(int, int)> calculations = _ruler.getDistanceBearing();
          List<LatLng> points = _ruler.getPoints();
          return MarkerLayer(
            markers: [
              for(LatLng point in points)
                Marker(point: point, child: const Icon(Icons.cancel_outlined, color: Colors.black,)),
              for(int calculationN = 0; calculationN < calculations.length; calculationN++)
                Marker(alignment: Alignment.bottomRight, point: points[calculationN + 1], width: 128, child: Text("${calculations[calculationN].$1.toString()}/${calculations[calculationN].$2.toString()}\u00b0", style: TextStyle(backgroundColor: Theme.of(context).cardColor.withOpacity(0.6)),))
            ],
          );
        },
      ),
    ));

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
        top: Constants.screenHeightForInstruments(context),
        child:Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width:width,
              height: height,
              child: ClipRRect(
                borderRadius: const BorderRadius.only( bottomRight: Radius.circular(40)),
                child:Opacity(opacity: _layersOpacity[_layers.indexOf('PFD')],
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
              if(_layersOpacity[_layers.indexOf('PFD')] > 0)
                pfd,
              Positioned(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(height: Constants.screenHeightForInstruments(context), child: const InstrumentList())
                )
              ),
              // warn
              Positioned(
                child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                        padding: EdgeInsets.fromLTRB(5, Constants.screenHeightForInstruments(context), 5, 5),
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
                          padding: EdgeInsets.fromLTRB(5, 5, 5, Constants.bottomPaddingSize(context) + iconRadius * 2 + 10), // buttons under have 5 padding and radius
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.all(5.0),
                              backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),
                            ),
                            onPressed: () {
                              Position p = Storage().position;
                              LatLng l = LatLng(p.latitude, p.longitude);
                              if(_northUp) {
                                // do not change zoom on center
                                _controller == null ? {} : _controller!.moveAndRotate(l, _controller!.camera.zoom, 0);// rotate to heading on center on track up
                              }
                              else {
                                _controller == null ? {} : _controller!.moveAndRotate(l, _controller!.camera.zoom, -p.heading);
                              }
                            },
                            onLongPress: () {
                              Position p = Storage().position;
                              LatLng l = LatLng(p.latitude, p.longitude);
                              if(_northUp) {
                                // do not change zoom on center
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
                          padding: EdgeInsets.fromLTRB(35, 0, 0, Constants.bottomPaddingSize(context) + iconRadius * 2 + 10),
                          child: Row(children:[
                            // menu
                            TextButton(
                              onPressed: () {
                                if(Storage().settings.shouldShowReview()) {
                                  showDialog(context: context, builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: const Text('Review AvareX?'),
                                      content: const Text("Hey Aviator! Loved using AvareX? We would love a quick review."),
                                      actions: <Widget>[
                                        TextButton(
                                          child: const Text('Yes'),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                            final InAppReview inAppReview = InAppReview.instance;
                                            inAppReview.openStoreListing(microsoftStoreId: Constants.microsoftId, appStoreId: Constants.appleId);
                                            Storage().settings.doneReview();
                                          },
                                        ),
                                        TextButton(
                                          child: const Text('Never'),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                            Storage().settings.doneReview();
                                          },
                                        ),
                                        TextButton(
                                          child: const Text('Later'),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                      ],
                                    );
                                  });
                                }
                                else {
                                  Scaffold.of(context).openDrawer();
                                }
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7)
                              ),
                              child: const Text("Menu"),
                            ),
                          ])
                      )
                  )
              ),

              Positioned(
                  child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(0, 0, 5, Constants.bottomPaddingSize(context)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end, children:[
                              Row(mainAxisAlignment: MainAxisAlignment.end,
                                children:[
                                  IconButton(
                                    tooltip: "Measure distances and bearings",
                                    onPressed: () {
                                      setState(() {
                                        if(_ruler.isMeasuring()) {
                                          _ruler.init();
                                        }
                                        else {
                                          _ruler.init();
                                          _ruler.startMeasure();
                                        }
                                      });
                                    },
                                    icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),
                                      child: Icon(MdiIcons.mathCompass, color: _ruler.color() == Colors.white ? Theme.of(context).colorScheme.primary : Colors.red, ))),

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
                                            return CircleAvatar(
                                                radius: iconRadius,
                                                backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),
                                                // in track up, rotate icon
                                                child: _northUp ? Tooltip(message: "Press to enable track up navigation", child: Icon(MdiIcons.navigation)) :
                                                Transform.rotate(
                                                    angle: value.heading * pi / 180,
                                                    child: Tooltip(message: "Press to enable North up navigation", child: Icon(MdiIcons.arrowUpThinCircleOutline))));
                                          }
                                      )),

                                  IconButton(
                                    tooltip: "Enable rubber banding",
                                    onPressed: () {
                                      setState(() {
                                        Storage().settings.isRubberBanding() ? Storage().settings.setRubberBanding(false) : Storage().settings.setRubberBanding(true);
                                      });
                                    },
                                    icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),
                                      child: Icon(MdiIcons.arrowDecisionOutline, color: Storage().settings.isRubberBanding() ? Colors.red : Theme.of(context).colorScheme.primary))),

                                  IconButton(
                                      tooltip: "Write a note",
                                      onPressed: () {
                                        setState(() {
                                          Navigator.pushNamed(context, '/notes');
                                        });
                                      },
                                      icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),
                                          child: Icon(MdiIcons.transcribe))),

                                  PopupMenuButton( // layer selection
                                    tooltip: "Select the chart type",
                                    icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),
                                        child: const Icon(Icons.photo_library_rounded)),
                                    initialValue: _type,
                                    itemBuilder: (BuildContext context) =>
                                        List.generate(_charts.length, (int index) => PopupMenuItem(child:
                                          ListTile(
                                            onTap: () {
                                              setState(() {
                                                Navigator.pop(context);
                                                _type = _charts[index];
                                                Storage().settings.setChartType(_charts[index]);
                                              });
                                            },
                                            dense: true,
                                            title: Text(_charts[index]),
                                            leading: Visibility(visible: _charts[index] == _type, child: const Icon(Icons.check),),
                                          ),
                                        ),)
                                  ),

                                  // switch layers on off
                                  PopupMenuButton( // layer selection
                                    tooltip: "Select the layers to show on the Map screen",
                                    icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),
                                        child: const Icon(Icons.layers)),
                                    initialValue: _layers[0],
                                    itemBuilder: (BuildContext context) =>
                                        List.generate(_layers.length, (int index) => PopupMenuItem(
                                          child: StatefulBuilder(
                                            builder: (context1, setState1) =>
                                                ListTile(
                                                  dense: true,
                                                  title: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                    Expanded(flex: 1, child:Text(_layers[index])),
                                                    Expanded(flex: 2, child:Slider(min: 0, max: 1, divisions: 4, // levels of opacity, 0 is off
                                                    value: _layersOpacity[index],
                                                    onChanged: (double value) {
                                                      setState1(() {
                                                        _layersOpacity[index] = value;
                                                      });
                                                      if(_layers[index] == "Tracks") {
                                                        if(value == 0) {
                                                          // save tracks on turning them off then show user where to get them
                                                          Storage().settings.setDocumentPage(DocumentsScreen.userDocuments);
                                                          Storage().tracks.saveKml().then((value) {
                                                            setState1(() {
                                                              Navigator.pop(context1);
                                                              Navigator.pushNamed(context1, '/documents');
                                                            });
                                                          });
                                                        }
                                                        else {
                                                          Storage().tracks.reset(); //on turning on, start fresh
                                                        }
                                                      }
                                                      if(_layers[index] == "OSM" && value > 0) {
                                                          _layersOpacity[_layers.indexOf("Topo")] = 0; // save memory by keeping layers to minimum
                                                      }
                                                      if(_layers[index] == "Topo" && value > 0) {
                                                        _layersOpacity[_layers.indexOf("OSM")] = 0; // save memory by keeping layers to minimum
                                                      }
                                                      if(_layers[index] == "Chart" && value > 0) {
                                                        _layersOpacity[_layers.indexOf("OpenAIP")] = 0; // save memory by keeping layers to minimum
                                                      }
                                                      if(_layers[index] == "OpenAIP" && value > 0) {
                                                        _layersOpacity[_layers.indexOf("Chart")] = 0; // save memory by keeping layers to minimum
                                                      }
                                                      // now save to settings
                                                      Storage().settings.setLayersOpacity(_layersOpacity);
                                                      setState(() {
                                                        _layersOpacity[index] = value; // this is the state for the map
                                                      });
                                                      // Turn audible alerts off and on depending on traffic layer
                                                      Storage().settings.setAudibleAlertsEnabled(_layersOpacity[Storage().settings.getLayers().indexOf("Traffic")] > 0);
                                                    },
                                                  )),
                                                ])),
                                          ),)
                                        ),
                                    ),
                                  // switch layers on off
                                ]
                              ),
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
    paintImage(canvas: canvas, rect:
      Rect.fromLTWH(0, size.height / 2 - size.width / 2, size.width, size.width), image: Storage().imagePlane!);
    _paintCenter.shader = ui.Gradient.linear(Offset(size.width / 2, size.height / 2 - size.width * 3 / 4), Offset(size.width / 2, 0), [Colors.red, Colors.white]);
    canvas.drawLine(Offset(size.width / 2, size.height / 2 - size.width * 3 / 4), Offset(size.width / 2, 0), _paintCenter);
    _paintCenter.shader = null;
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

    // get file to download message in tile missing
    String name = Chart.getChartRegion(coordinates.x, coordinates.y, coordinates.z);
    if(name.isEmpty) {
      return const AssetImage("assets/images/512.png");
    }
    return AssetImage("assets/images/dl_$name.png");
  }
}

// for scale measurement
class Ruler {

  List<Destination> _points = [];
  bool _measuring = false;
  final change = ValueNotifier<int>(0);
  final GeoCalculations geo = GeoCalculations();

  void init() {
    _points = [];
    _measuring = false;
    change.value++;
  }

  void setPointer(int id, LatLng position) {
    if(!_measuring) {
      return;
    }

    _points.add(Destination.fromLatLng(position));
    change.value++;
  }

  List<LatLng> getPoints() {
    return _points.map((e) => e.coordinate).toList();
  }

  List<(int, int)> getDistanceBearing() {
    List<(int, int)> ret = [];
    if(_points.length < 2) {
      return ret;
    }
    for(int i = 0; i < _points.length - 1; i++) {
      double variation = _points[i].geoVariation?? 0;
      double bearing = GeoCalculations.getMagneticHeading(geo.calculateBearing(_points[i].coordinate, _points[i + 1].coordinate), variation);
      double distance = geo.calculateDistance(_points[i].coordinate, _points[i + 1].coordinate);
      ret.add((distance.round(), bearing.round()));
    }

    return ret;
  }

  Color color() {
    if(_measuring) {
      return Colors.red;
    }
    return Colors.white;
  }

  void startMeasure() {
    _measuring = true;
  }

  bool isMeasuring() {
    return _measuring;
  }

}
