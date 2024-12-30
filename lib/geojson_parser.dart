import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geojson_vi/geojson_vi.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:latlong2/latlong.dart';

class GeoJsonParser {

  List<Polygon> polygons = [];
  List<Marker> markers = [];

  ValueNotifier<int> change = ValueNotifier<int>(0);

  void _addMarker(GeoJSONPoint mp, String label) {
    if (mp.coordinates.length > 1) {
      markers.add(Marker(
          point: LatLng(mp.coordinates[1], mp.coordinates[0]),
          child: JustTheTooltip(
              content: Container(padding: const EdgeInsets.all(5), child:Text(label)),
              triggerMode: TooltipTriggerMode.tap,
              waitDuration: const Duration(seconds: 1),
              child: const Icon(Icons.location_pin, color: Colors.black,))));
    }
  }

  void _addPolygon(List<List<List<double>>> coordinates, String label) {
    for (var ring in coordinates) {
      if (ring.isNotEmpty) {
        List<LatLng> ll = ring.map((point) => LatLng(point[1], point[0])).toList();
        polygons.add(Polygon(
          points: ll,
          label: label,
          labelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 12),
          isFilled: false,
          borderStrokeWidth: 2,
          borderColor: Colors.black,
        ));
      }
    }
  }

  void _processGeometry(GeoJSONGeometry geometry, String label) {
    label = label.replaceAll(",", "\n");
    label = label.substring(1, label.length - 2); // remove { and }

    if (geometry.type == GeoJSONType.point) {
      _addMarker(geometry as GeoJSONPoint, label);
    }
    if (geometry.type == GeoJSONType.multiPoint) {
      for (var point in (geometry as GeoJSONMultiPoint).coordinates) {
        _addMarker(point as GeoJSONPoint, label);
      }
    }
    else if (geometry.type == GeoJSONType.polygon) {
      _addPolygon((geometry as GeoJSONPolygon).coordinates, label);
    }
    else if (geometry.type == GeoJSONType.multiPolygon) {
      for (var polygon in (geometry as GeoJSONMultiPolygon).coordinates) {
        _addPolygon(polygon, label);
      }
    }
  }

  Future<void> parse(String json) async {
    polygons.clear();
    markers.clear();
    var gj = GeoJSON.fromJSON(json);

    if (gj.type == GeoJSONType.feature) {
      var feature = gj as GeoJSONFeature;
      if (feature.geometry != null) {
        _processGeometry(feature.geometry!, feature.properties == null ? "" : feature.properties.toString());
      }
    } else if (gj.type == GeoJSONType.featureCollection) {
      var fc = gj as GeoJSONFeatureCollection;
      for (var feature in fc.features) {
        if(feature != null) {
          if (feature.geometry != null) {
            _processGeometry(feature.geometry!, feature.properties == null ? "" : feature.properties.toString());
          }
        }
      }
    }
    change.value++;
  }
}

