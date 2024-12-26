import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geojson_vi/geojson_vi.dart';
import 'package:latlong2/latlong.dart';

class GeoJsonParser {

  List<Polygon> polygons = [];
  List<Marker> markers = [];

  ValueNotifier<int> change = ValueNotifier<int>(0);

  void parse(String json) {
    var gj = GeoJSON.fromJSON(json);
    polygons.clear();
    markers.clear();

    void addMarker(GeoJSONPoint mp) {
      if (mp.coordinates.length > 1) {
        markers.add(Marker(
            point: LatLng(mp.coordinates[1], mp.coordinates[0]),
            child: const Icon(Icons.location_pin, color: Colors.black,)));
      }
    }

    void addPolygon(List<List<List<double>>> coordinates) {
      for (var ring in coordinates) {
        if (ring.isNotEmpty) {
          List<LatLng> ll = ring.map((point) => LatLng(point[1], point[0])).toList();
          polygons.add(Polygon(
            points: ll,
            isFilled: false,
            borderStrokeWidth: 2,
            borderColor: Colors.black,
          ));
        }
      }
    }

    void processGeometry(GeoJSONGeometry geometry) {
      if (geometry.type == GeoJSONType.point) {
        addMarker(geometry as GeoJSONPoint);
      }
      if (geometry.type == GeoJSONType.multiPoint) {
        for (var point in (geometry as GeoJSONMultiPoint).coordinates) {
          addMarker(point as GeoJSONPoint);
        }
      }
      else if (geometry.type == GeoJSONType.polygon) {
        addPolygon((geometry as GeoJSONPolygon).coordinates);
      }
      else if (geometry.type == GeoJSONType.multiPolygon) {
        for (var polygon in (geometry as GeoJSONMultiPolygon).coordinates) {
          addPolygon(polygon);
        }
      }
    }

    if (gj.type == GeoJSONType.feature) {
      var feature = gj as GeoJSONFeature;
      if (feature.geometry != null) {
        processGeometry(feature.geometry!);
      }
    } else if (gj.type == GeoJSONType.featureCollection) {
      var fc = gj as GeoJSONFeatureCollection;
      for (var feature in fc.features) {
        if(feature != null) {
          if (feature.geometry != null) {
            processGeometry(feature.geometry!);
          }
        }
      }
    }
    change.value++;
  }
}

