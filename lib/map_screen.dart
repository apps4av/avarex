import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/app_log.dart';
import 'package:avaremp/destination/airport.dart';
import 'package:avaremp/documents_screen.dart';
import 'package:avaremp/gdl90/nexrad_cache.dart';
import 'package:avaremp/gdl90/traffic_cache.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/gps_recorder.dart';
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
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:toastification/toastification.dart';
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

  final List<String> _charts = DownloadScreenState.getCategories();
  LatLng? _previousPosition;
  bool _interacting = false;
  bool _rubberBanding = false;
  final Ruler _ruler = Ruler();
  String _type = Storage().settings.getChartType();
  int _maxZoom = ChartCategory.chartTypeToZoom(Storage().settings.getChartType());
  final MapController _controller = MapController();
  // get layers and states from settings
  final List<String> _layers = Storage().settings.getLayers();
  final List<double> _layersOpacity = Storage().settings.getLayersOpacity();
  final int _disableClusteringAtZoom = 10;
  final int _maxClusterRadius = 160;
  bool _northUp = Storage().settings.getNorthUp();
  final GeoCalculations _calculations = GeoCalculations();
  final ValueNotifier<(List<LatLng>, List<String>)> _tapeNotifier = ValueNotifier<(List<LatLng>, List<String>)>(([],[]));
  double _nexradOpacity = 0;

  static final List<String> _mesonets = [
    "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m40m/{z}/{x}/{y}.png",
    "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m30m/{z}/{x}/{y}.png",
    "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m20m/{z}/{x}/{y}.png",
    "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m10m/{z}/{x}/{y}.png",
    "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png"
  ];

  TileLayer _nexradLayer = TileLayer(
    maxNativeZoom: 5,
    urlTemplate: _mesonets[0],
    tileProvider: NetworkTileProvider(),
  );

  final TileLayer _osmLayer = TileLayer(
    urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    tileProvider: MapNetworkTileProvider());

  final TileLayer _openaipLayer = TileLayer(
      maxNativeZoom: 16,
      urlTemplate: "https://api.tiles.openaip.net/api/data/openaip/{z}/{x}/{y}.png?apiKey=@@___openaip_client_id__@@",
      tileProvider: MapNetworkTileProvider());

  final TileLayer _topoLayer = TileLayer(
    maxNativeZoom: 16,
    urlTemplate: "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/WMTS/tile/1.0.0/USGSTopo/default/default028mm/{z}/{y}/{x}.png",
    tileProvider: MapNetworkTileProvider()
  );

  static Future<void> showDestination(BuildContext context, List<Destination> destinations) async {
    await Navigator.pushNamed(context, "/popup", arguments: destinations);
  }

  void _metarListen() {
    setState(() {
      _metarCluster = null;
    });
  }

  void _tafListen() {
    setState(() {
      _tafCluster = null;
    });
  }

  void _airepListen() {
    setState(() {
      _airepCluster = null;
    });
  }

  void _airSigmetListen() {
    setState(() {
      _airSigmetCluster = null;
      _airSigmetLayer = null;
    });
  }

  void _tfrListen() {
    setState(() {
      _tfrCluster = null;
      _tfrLayer = null;
    });
  }

  void _geoJsonListen() {
    setState(() {
      _geojsonCluster = null;
      _geoJsonLayer = null;
    });
  }

  static void showToast(BuildContext context, String text, Widget? icon, int duration) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    Toastification().dismissAll();
    Toastification().show(
        alignment: Alignment.bottomRight,
        context: context,
        closeOnClick: true,
        closeButton: ToastCloseButton(showType: CloseButtonShowType.none),
        description: Text(text, style: TextStyle(fontWeight: FontWeight.w500),),
        autoCloseDuration: Duration(seconds: duration),
        icon: CircleAvatar(radius: 16, backgroundColor: Colors.white, child: icon),
        showIcon: icon == null ? false : true,
        backgroundColor: colorScheme.surfaceDim, // Using a theme color
        foregroundColor: colorScheme.onSurface, // Using a theme c
    );
  }

  @override
  void initState() {
    // move with airplane but do not hold the map
    Storage().gpsChange.addListener(_gpsListen);
    Storage().metar.change.addListener(_metarListen);
    Storage().taf.change.addListener(_tafListen);
    Storage().airep.change.addListener(_airepListen);
    Storage().airSigmet.change.addListener(_airSigmetListen);
    Storage().tfr.change.addListener(_tfrListen);
    Storage().geoParser.change.addListener(_geoJsonListen);
    super.initState();
  }

  @override
  void dispose() {
    // save ptz when we switch out
    Storage().gpsChange.removeListener(_gpsListen);
    Storage().metar.change.removeListener(_metarListen);
    Storage().taf.change.removeListener(_tafListen);
    Storage().airep.change.removeListener(_airepListen);
    Storage().airSigmet.change.removeListener(_airSigmetListen);
    Storage().tfr.change.removeListener(_tfrListen);
    Storage().geoParser.change.removeListener(_geoJsonListen);
    _previousPosition = null;
    super.dispose();
  }

  // for measuring tape
  void _handleEvent(MapEvent mapEvent) {
    LatLng center = Gps.toLatLng(Storage().gpsChange.value);
    LatLng topCenter = _controller.camera.pointToLatLng(Point(Constants.screenWidth(context) / 2, Constants.screenHeightForInstruments(context) + iconRadius));
    String centralDistance = _calculations.calculateDistance(center, topCenter).round().toString();
    LatLng topLeft = _controller.camera.pointToLatLng(const Point(iconRadius, 0));
    LatLng bottomLeft = _controller.camera.pointToLatLng(Point(iconRadius, Constants.screenHeight(context)));
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
      double d = _calculations.calculateDistance(LatLng(center.latitude, avgLon), ll);
      distanceVertical.add(d.round().toString());
      llVertical.add(ll);
    }
    for (double latitude = center.latitude; latitude > bottomLeft.latitude; latitude -= ticksInLatitude) {
      if (latitude > topLeft.latitude || latitude < bottomLeft.latitude) {
        continue; // outside of view area
      }
      double avgLon = (bottomLeft.longitude + topLeft.longitude) / 2;
      LatLng ll = LatLng(latitude, avgLon);
      double d = _calculations.calculateDistance(LatLng(center.latitude, avgLon), ll);
      distanceVertical.add(d.round().toString());
      llVertical.add(ll);
    }
    _tapeNotifier.value = (llVertical + [topCenter], distanceVertical + [centralDistance]);
  }

  // this pans camera on move
  void _gpsListen() {
    final LatLng cur = Gps.toLatLng(Storage().position);
    _previousPosition ??= cur;
    try {
      LatLng diff = LatLng(cur.latitude - _previousPosition!.latitude,
          cur.longitude - _previousPosition!.longitude);
      LatLng now = _controller.camera.center;
      LatLng next = LatLng(
          now.latitude + diff.latitude, now.longitude + diff.longitude);
      if (!_interacting) { // do not move when user is moving map
        _controller.moveAndRotate(next, _controller.camera.zoom,
            _northUp ? 0 : -Storage().position.heading);
      }
    }
    catch (e) {
      AppLog.logMessage("MapScreen: GPS listen error $e");
    } // adding to lat lon is dangerous

    _previousPosition = Gps.toLatLng(Storage().position);
  }

  PolylineLayer? _tfrLayer;
  PolylineLayer _makeTfrLayer() {
    List<Weather> weather = Storage().tfr.getAll();
    List<Tfr> tfrs = weather.map((e) => e as Tfr).toList();
    _tfrLayer ??= PolylineLayer(
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

    return _tfrLayer!;
  }

  PolylineLayer? _airSigmetLayer;
  PolylineLayer _makeAirSigmetLayer() {
    List<Weather> weather = Storage().airSigmet.getAll();
    List<AirSigmet> airSigmet = weather.map((e) => e as AirSigmet).toList();
    _airSigmetLayer ??= PolylineLayer(
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

    return _airSigmetLayer!;
  }

  PolygonLayer? _geoJsonLayer;
  PolygonLayer _makeGeoJsonLayer() {
    _geoJsonLayer ??= PolygonLayer(polygons: Storage().geoParser.polygons);
    return _geoJsonLayer!;
  }

  MarkerClusterLayerWidget makeCluster(List<Marker> markers) {
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
          showPolygon: false,
          spiderfyCluster: false,
          maxClusterRadius: _maxClusterRadius,
          disableClusteringAtZoom: _disableClusteringAtZoom,
          markers: markers,
          builder: (context, m) {
            return Container(color: Colors.transparent,);
          },
        )
    );
  }

  // this should not rebuild till weather is updated
  MarkerClusterLayerWidget? _metarCluster;
  MarkerClusterLayerWidget _makeMetarCluster() {
    List<Weather> weather = Storage().metar.getAll();
    List<Metar> metars = weather.map((e) => e as Metar).toList();
    _metarCluster ??= makeCluster([
            for(Metar m in metars)
              Marker(point: m.coordinate,
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        showToast(context, m.toString(), m.getIcon(), 30);
                      });
                    },
                    child: m.getIcon(),
                  )
              )
          ],
        );
    return _metarCluster!;
  }

  // this should not rebuild till weather is updated
  MarkerClusterLayerWidget? _tafCluster;
  MarkerClusterLayerWidget _makeTafCluster() {
    List<Weather> weather = Storage().taf.getAll();
    List<Taf> tafs = weather.map((e) => e as Taf).toList();
    _tafCluster ??= makeCluster([
      for(Taf t in tafs)
        Marker(point: t.coordinate,
            width: 32,
            height: 32,
            alignment: Alignment.bottomRight,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  showToast(context, t.toString(), t.getIcon(), 30);
                });
              },
              child: t.getIcon(),))
    ]);
    return _tafCluster!;
  }

  // this should not rebuild till weather is updated
  MarkerClusterLayerWidget? _airepCluster;
  MarkerClusterLayerWidget _makeAirepCluster() {
    List<Weather> weather = Storage().airep.getAll();
    List<Airep> aireps = weather.map((e) => e as Airep).toList();
    _airepCluster ??= makeCluster([
            for(Airep a in aireps)
              Marker(point: a.coordinates,
                  alignment: Alignment.bottomLeft,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        showToast(context, a.toString(), const Icon(Icons.person, color: Colors.black,), 30);
                      });
                    },
                    child: const Icon(Icons.person, color: Colors.black,),))
          ],
    );

    return _airepCluster!;
  }

  // this should not rebuild till weather is updated
  MarkerClusterLayerWidget? _airSigmetCluster;
  MarkerClusterLayerWidget _makeAirSigmetCluster() {
    List<Weather> weather = Storage().airSigmet.getAll();
    List<AirSigmet> airSigmet = weather.map((e) => e as AirSigmet).toList();
    _airSigmetCluster ??= makeCluster([
            for(AirSigmet a in airSigmet)
              if(a.coordinates.isNotEmpty)
                Marker(
                    point: a.coordinates[0],
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          showToast(context, "${a.toString()}\n** Long press to show/hide the covered area **", Icon(Icons.ac_unit_rounded,color: a.getColor()), 30);
                        });
                      },
                      onLongPress: () {
                        setState(() {
                          _airSigmetLayer = null; // rebuild layer with visible shapes
                          a.showShape = !a.showShape;
                        });
                      },
                      child: Icon(Icons.ac_unit_rounded,
                          color: a.getColor()
                      )

                    )

                )
          ],
        );

    return _airSigmetCluster!;
  }

  MarkerClusterLayerWidget? _tfrCluster;
  MarkerClusterLayerWidget _makeTfrCluster() {
    List<Weather> weather = Storage().tfr.getAll();
    List<Tfr> tfrs = weather.map((e) => e as Tfr).toList();
    _tfrCluster ??= makeCluster([
            for(Tfr t in tfrs)
              if(t.coordinates.isNotEmpty)
                Marker(point: t.coordinates[t.getLabelCoordinate()],
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          showToast(context, t.toString(), Icon(MdiIcons.clockAlert, color: Colors.black,), 30);
                        });
                      },
                      child: Icon(MdiIcons.clockAlert, color: Colors.black,),))
          ],
        );
    return _tfrCluster!;
  }

  MarkerClusterLayerWidget? _geojsonCluster;
  MarkerClusterLayerWidget _makeGeoJsonCluster() {
    _geojsonCluster ??= makeCluster(Storage().geoParser.markers);

    return _geojsonCluster!;
  }


  @override
  Widget build(BuildContext context) {

    double opacity = 1.0;

    final String index = ChartCategory.chartTypeToIndex(_type);
    _maxZoom = ChartCategory.chartTypeToZoom(_type);

    //add layers
    final List<Widget> layers = [];

    final TileLayer chartLayer = TileLayer(
        tms: true,
        maxNativeZoom: _maxZoom,
        tileProvider: ChartTileProvider(),
        urlTemplate: "${Storage().dataDir}/tiles/$index/{z}/{x}/{y}.webp");

    // start from known location
    final MapOptions opts = MapOptions(
      initialCenter: LatLng(Storage().settings.getCenterLatitude(),
          Storage().settings.getCenterLongitude()),
      initialZoom: Storage().settings.getZoom(),
      minZoom: 2,
      // this is less crazy
      maxZoom: 20,
      // max for USGS
      interactionOptions: InteractionOptions(flags: _northUp
          ? InteractiveFlag.all & (~InteractiveFlag.doubleTapDragZoom) & (~InteractiveFlag.rotate)
          : InteractiveFlag.all & (~InteractiveFlag.doubleTapDragZoom)),
      // no rotation in track up
      initialRotation: Storage().settings.getRotation(),
      backgroundColor: Storage().settings.isLightMode() ? Constants.mapBackgroundColorLight: Constants.mapBackgroundColorDark,
      onLongPress: (tap, point) async {
        if(_ruler.isMeasuring()) {
          _ruler.setPoint(point); // on long press when measuring, set ruler point
        }
        else { // otherwise show destination screen
          List<Destination> items = await MainDatabaseHelper.db.findNear(point);
          setState(() {
            showDestination(this.context, items);
          });
        }
      },
      onMapEvent: (MapEvent mapEvent) {
        if(mapEvent is MapEventLongPress) {
          // dismiss all dialogs
          Toastification().dismissAll();
        }
        if(mapEvent is MapEventTap) {
          // dismiss all dialogs
          Toastification().dismissAll();
        }
        if (mapEvent is MapEventMoveStart) {
          // do something
          _interacting = true;
          Toastification().dismissAll();
        }
        if (mapEvent is MapEventMoveEnd) {
          // save location for next start
          showOnMap(_controller.camera.center);
          Storage().settings.setZoom(_controller.camera.zoom);
          Storage().settings.setRotation(_controller.camera.rotation);
          _interacting = false;
        }
        _handleEvent(mapEvent);
      },
    );

    int lIndex = _layers.indexOf('OSM');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(Opacity(opacity: opacity, child: _osmLayer));
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
      layers.add(Opacity(opacity: opacity, child: _topoLayer));
    }
    lIndex = _layers.indexOf('OpenAIP');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(Opacity(opacity: opacity, child: _openaipLayer));
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
      layers.add(Opacity(opacity: opacity, child: _makeGeoJsonLayer()));

      layers.add(Opacity(opacity: opacity, child: _makeGeoJsonCluster()));
    }

    lIndex = _layers.indexOf('Radar');
    opacity = _layersOpacity[lIndex];
    _nexradOpacity = opacity;
    if (opacity > 0) {
      layers.add(Opacity(opacity: _nexradOpacity,
        child: ValueListenableBuilder<int>(
          valueListenable: Storage().timeRadarChange,
          builder: (context, value, _) {
            int index = value % (_mesonets.length * 2);
            if(index > _mesonets.length - 1) {
              index = _mesonets.length - 1; // give 2 times the time for latest to stay on
            }
            _nexradLayer = TileLayer(
              maxNativeZoom: 5,
              urlTemplate: _mesonets[index],
              tileProvider: NetworkTileProvider(),
            );
            return _nexradLayer;
          },
        )));

      layers.add(// nexrad slider
          Opacity(opacity: opacity, child: Container(height: 30, width: Constants.screenWidth(context) / 3, padding: EdgeInsets.fromLTRB(10, Constants.screenHeightForInstruments(context) + 20, 0, 0),
            child: ValueListenableBuilder<int>(
              valueListenable: Storage().timeRadarChange,
              builder: (context, value, _) {
                int index = value % (_mesonets.length * 2);
                if(index > _mesonets.length - 1) {
                  index = _mesonets.length - 1; // give 2 times the time for latest to stay on
                }
                return Slider(value: index / (_mesonets.length - 1), onChanged: (double value) {  });
          }),
      )));
    }

    lIndex = _layers.indexOf('Weather');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(
        // nexrad layer
          IgnorePointer(child:Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
            valueListenable: Storage().timeChange,
            builder: (context, value, _) {
              bool conus = true;
              // show conus above zoom level 7
              conus = _controller.camera.zoom < 7 ? true : false;
              List<NexradImage> images = conus ? Storage().nexradCache.getNexradConus() : Storage().nexradCache.getNexrad();
              return OverlayImageLayer(
                overlayImages: images.map((e) {
                  return OverlayImage(imageProvider: MemoryImage(e.getImage()!),
                      bounds: e.getBounds());
                }).toList(),
              );
            },
          ),
          ))
      );

      layers.add(Opacity(opacity: opacity, child: _makeMetarCluster()));

      layers.add(Opacity(opacity: opacity, child: _makeTafCluster()));

      layers.add(Opacity(opacity: opacity, child: _makeAirepCluster()));

      layers.add(Opacity(opacity: opacity, child: _makeAirSigmetLayer()));

      layers.add(Opacity(opacity: opacity, child: _makeAirSigmetCluster()));

    }

    lIndex = _layers.indexOf('TFR');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(IgnorePointer(child: Opacity(opacity: opacity, child: _makeTfrLayer())));

      layers.add(Opacity(opacity: opacity, child: _makeTfrCluster()));
    }

    lIndex = _layers.indexOf('Plate');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add( // circle layer
        IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
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
      )));
    }

    lIndex = _layers.indexOf('Traffic');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add(
        // traffic layer
          IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
          valueListenable: Storage().timeChange,
          builder: (context, value, _) {
            double angle = _northUp ? 0 : Storage().position.heading;
            return MarkerLayer(
              markers:
              Storage().trafficCache.getTraffic().map((e) {
                return Marker( // our position and heading to destination
                  point: e.getCoordinates(),
                  child: Transform.rotate(angle: angle * pi / 180, child:e.getIcon(Storage().settings.isAudibleAlertsEnabled(), angle)),
                );
              }).toList(),
            );
          },
        ),
      )));
    }

    lIndex = _layers.indexOf('Tracks');
    opacity = _layersOpacity[lIndex];
    if (opacity > 0) {
      layers.add( // tracks layer
          IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<Position>(
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
      )));
    }

    lIndex = _layers.indexOf('Circles');
    opacity = _layersOpacity[lIndex];
    if(opacity > 0) {

      layers.add( // circle layer
        IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<Position>(
            valueListenable: Storage().gpsChange,
            builder: (context, value, _) {
              return PolylineLayer(
                polylines: [
                  // 10 nm circle
                  Polyline(
                    points: GeoCalculations().calculateCircle(Gps.toLatLng(value), 10),
                    color: Constants.distanceCircleColor,
                    strokeWidth: 3,
                  ),
                  // 5 nm circle
                  Polyline(
                    points: GeoCalculations().calculateCircle(Gps.toLatLng(value), 5),
                    color: Constants.distanceCircleColor,
                    strokeWidth: 3,
                  ),
                  // 2 nm circle
                  Polyline(
                    points: GeoCalculations().calculateCircle(Gps.toLatLng(value), 2),
                    color: Constants.distanceCircleColor,
                    strokeWidth: 3,
                  ),
                  // speed marker
                  Polyline(
                    points: GeoCalculations().calculateCircle(Gps.toLatLng(value), GeoCalculations.convertSpeed(value.speed) / 60),
                    color: Constants.speedCircleColor,
                    strokeWidth: 3,
                  ),
                ],
              );
            },
          ),
          )
      ));

      layers.add( // circle layer labels
          IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<Position>(
            valueListenable: Storage().gpsChange,
            builder: (context, value, _) {
              return MarkerLayer(
                markers: [
                  Marker(point: GeoCalculations().calculateOffset(
                      Gps.toLatLng(value), 10, -30),
                      child: Transform.rotate(
                          angle: _northUp ? 0 : Storage().position.heading * pi /
                              180, child:
                      CircleAvatar(
                          backgroundColor: Constants.bottomNavBarBackgroundColor,
                          child: const Text("10", style: TextStyle(fontSize: 14,
                            color: Colors.white,),)))),
                  Marker(point: GeoCalculations().calculateOffset(
                      Gps.toLatLng(value), 5, -30),
                      child: Transform.rotate(
                          angle: _northUp ? 0 : Storage().position.heading * pi /
                              180, child:
                      CircleAvatar(
                          backgroundColor: Constants.bottomNavBarBackgroundColor,
                          child: const Text("5", style: TextStyle(fontSize: 14,
                            color: Colors.white,),)))),
                  Marker(point: GeoCalculations().calculateOffset(
                      Gps.toLatLng(value), 2, -30),
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
          )));
    }

    lIndex = _layers.indexOf('Tape');
    opacity = _layersOpacity[lIndex];
    if(opacity > 0) {
      layers.add( // tape
          IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<(List<LatLng>, List<String>)>(
            valueListenable: _tapeNotifier,
            builder: (context, value, _) {
              return MarkerLayer(
                  markers: [
                    for(int index = 0; index < value.$1.length; index++)
                      Marker(point: value.$1[index], width: 32, alignment: Alignment.center,
                          child: Container(width: 32,
                              decoration: BoxDecoration(borderRadius: const BorderRadius.all(Radius.circular(12)), color: Theme.of(context).cardColor.withValues(alpha: 0.6)),
                              child: SizedBox(width: 32, child: FittedBox(
                                  child: Padding(padding: const EdgeInsets.all(3),
                                      child:Text(value.$2[index], style: const TextStyle(fontWeight: FontWeight.w600),)))
                              ))
                      ),
                  ]
              );
            },
          ),
          )));
      }


      lIndex = _layers.indexOf('Obstacles');
      opacity = _layersOpacity[lIndex];
      if (opacity > 0) {
        //obstacles
        layers.add(
            Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
                valueListenable: Storage().area.change,
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
          IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
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
      )));

      layers.add( // route layer for runway numbers
        IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
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
      )));

      layers.add( // brown track layer for airplane to waypoint
        IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
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
      )));

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
                                if(_rubberBanding) { // start rubber banding
                                  LatLng l = _controller.camera.pointToLatLng(Point(details.globalPosition.dx, details.globalPosition.dy));
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
                                LatLng l = _controller.camera.pointToLatLng(Point(details.globalPosition.dx, details.globalPosition.dy));
                                Storage().route.replaceDestinationFromDb(index, l);
                                Storage().rubberBandChange.value++;
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
                                if(_rubberBanding) { // start rubber banding
                                  LatLng l = _controller.camera.pointToLatLng(Point(details.globalPosition.dx, details.globalPosition.dy));
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
                                LatLng l = _controller.camera.pointToLatLng(Point(details.globalPosition.dx, details.globalPosition.dy));
                                Storage().route.replaceDestinationFromDb(index, l);
                                Storage().rubberBandChange.value++;
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
        // dont want this layer to be touchable so we ignore pointer so it does not get in the way of map interaction
        IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<Position>(
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
      )));

    } // all nav layers

    // ruler, always present
    layers.add(
      IgnorePointer(child: Opacity(opacity: opacity, child: ValueListenableBuilder<int>(
        valueListenable: _ruler.change,
        builder: (context, value, _) {
          List<(int, int)> calculations = _ruler.getDistanceBearing();
          List<LatLng> points = _ruler.getPoints();
          return MarkerLayer(
            markers: [
              for(LatLng point in points)
                Marker(point: point, child: const Icon(Icons.cancel_outlined, color: Colors.black,)),
              for(int calculationN = 0; calculationN < calculations.length; calculationN++)
                Marker(alignment: Alignment.bottomRight, point: points[calculationN + 1], width: 128, child: Text("${calculations[calculationN].$1.toString()}/${calculations[calculationN].$2.toString()}\u00b0", style: TextStyle(backgroundColor: Theme.of(context).cardColor.withValues(alpha: 0.6)),))
            ],
          );
        },
      ),
    )));

    final FlutterMap map = FlutterMap(
      mapController: _controller,
      options: opts,
      children: layers,
    );

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

    return Scaffold(
        endDrawer: Padding(padding: EdgeInsets.fromLTRB(0, Constants.screenHeight(context) / 8, 0, Constants.screenHeight(context) / 10),
            child: ValueListenableBuilder<bool>(
                valueListenable: Storage().warningChange,
                builder: (context, value, _) {
                  return WarningsWidget(gpsNotPermitted: Storage().gpsNotPermitted,
                    gpsDisabled: Storage().gpsDisabled, chartsMissing: Storage().chartsMissing,
                    dataExpired: Storage().dataExpired,
                    signed: Storage().settings.isSigned(),
                    gpsNoLock: Storage().gpsNoLock, exceptions: Storage().getExceptions());
                }
            )
        ),
        endDrawerEnableOpenDragGesture: false,
        body: Stack(
            children: [
              map, // map
              if(_layersOpacity[_layers.indexOf('PFD')] > 0)
                ValueListenableBuilder<int>(
                  valueListenable: Storage().pfdChange,
                  builder: (context, value, _) {
                    return Positioned(
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
                  }
                ),
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
                    alignment: Alignment.bottomRight,
                    child: Padding(
                        padding: EdgeInsets.fromLTRB(5, 5, 5, Constants.bottomPaddingSize(context) + iconRadius * 2 + 10), // buttons under have 5 padding and radius
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          // switch audio on off
                          if(_layersOpacity[_layers.indexOf("Traffic")] > 0)
                            IconButton(
                                tooltip: "Mute audible alerts",
                                onPressed: () {
                                  setState(() {
                                    Storage().settings.setAudibleAlertsEnabled(!Storage().settings.isAudibleAlertsEnabled());
                                  });
                                },
                                icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
                                    child: Storage().settings.isAudibleAlertsEnabled() ? const Icon(Icons.volume_up) : const Icon(Icons.volume_off))),
                          if(_layersOpacity[_layers.indexOf("Traffic")] > 0)
                            IconButton(
                                tooltip: "Traffic 'hockey puck' size",
                                onPressed: () {
                                  setState(() {
                                    Storage().settings.setTrafficPuckSize(TrafficCache.adjustPuck(Storage().settings.getTrafficPuckSize()));
                                  });
                                  Storage().trafficCache.changeArea(Storage().settings.getTrafficPuckSize());
                                },
                                icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
                                    child: Text(Storage().settings.getTrafficPuckSize()))
                            ),

                        ]
                      )
                    )
                )
              ),
              Positioned(
                  child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(5, 5, 5, Constants.bottomPaddingSize(context) + iconRadius * 2 + 10), // buttons under have 5 padding and radius
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.all(5.0),
                              backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
                            ),
                            onPressed: () {
                              Position p = Storage().position;
                              LatLng l = LatLng(p.latitude, p.longitude);
                              if(_northUp) {
                                // do not change zoom on center
                                _controller.moveAndRotate(l, _controller.camera.zoom, 0);// rotate to heading on center on track up
                              }
                              else {
                                _controller.moveAndRotate(l, _controller.camera.zoom, -p.heading);
                              }
                            },
                            onLongPress: () {
                              Position p = Storage().position;
                              LatLng l = LatLng(p.latitude, p.longitude);
                              if(_northUp) {
                                // do not change zoom on center
                                _controller.moveAndRotate(l, _maxZoom.toDouble(), 0);// rotate to heading on center on track up
                              }
                              else {
                                _controller.moveAndRotate(l, _maxZoom.toDouble(), -p.heading);
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
                                if(Storage().settings.shouldShowReview() && Constants.shouldShouldReview) {
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
                                backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7)
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
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:
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
                                    icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
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
                                                backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
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
                                    icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
                                      child: Icon(MdiIcons.arrowDecisionOutline, color: Storage().settings.isRubberBanding() ? Colors.red : Theme.of(context).colorScheme.primary))),

                                  IconButton(
                                      tooltip: "Write a note",
                                      onPressed: () {
                                        setState(() {
                                          Navigator.pushNamed(context, '/notes');
                                        });
                                      },
                                      icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
                                          child: Icon(MdiIcons.transcribe))),

                                  PopupMenuButton( // layer selection
                                    tooltip: "Select the chart type",
                                    icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
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
                                    icon: CircleAvatar(radius: iconRadius, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
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
                                                              if(value != null) {
                                                                showToast(context, "Track saved to Documents as $value.", Icon(Icons.info, color: Colors.black,), 3);
                                                              }
                                                              else {
                                                                showToast(context, "Unable to save tracks due to error.", Icon(Icons.info, color: Colors.black,), 3);
                                                              }
                                                            });
                                                          });
                                                        }
                                                        else {
                                                          Storage().tracks = GpsRecorder(); //on turning on, start fresh
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
                                                      Storage().settings.setAudibleAlertsEnabled(_layersOpacity[_layers.indexOf("Traffic")] > 0);
                                                    },
                                                  )),
                                                ])),
                                          ),)
                                        ),
                                    ),
                                ]
                              ),
                          )
                      )
                  )
              )
            ]
        )
    );
  }

  // set it in settings so map can show it
  static void showOnMap(LatLng coordinate) {
    Storage().settings.setCenterLongitude(coordinate.longitude);
    Storage().settings.setCenterLatitude(coordinate.latitude);
    Storage().settings.setZoom(ChartCategory.chartTypeToZoom(Storage().settings.getChartType()).toDouble());
  }
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

  void setPoint(LatLng position) {
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

class MapNetworkTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    String url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(url, cacheManager: FileCacheManager().mapCacheManager);
  }
}
