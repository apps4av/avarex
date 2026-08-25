import 'package:xml/xml.dart';

import 'ofmx_units.dart';

class OfmxImportResult {
  final List<Map<String, Object?>> airports;
  final List<Map<String, Object?>> airportComms;
  final List<Map<String, Object?>> runways;
  final List<Map<String, Object?>> runwayEnds;
  final List<Map<String, Object?>> waypoints;
  final List<Map<String, Object?>> airspaces;
  final List<Map<String, Object?>> airspaceVertices;

  const OfmxImportResult({
    required this.airports,
    required this.airportComms,
    required this.runways,
    required this.runwayEnds,
    required this.waypoints,
    required this.airspaces,
    required this.airspaceVertices,
  });
}

class OfmxImporter {
  OfmxImporter._();

  static OfmxImportResult parse(
    String xml, {
    required String region,
    required String cycle,
  }) {
    final document = XmlDocument.parse(xml);
    final airports = document.findAllElements('Ahp').map((e) => _airport(e, region, cycle)).whereType<Map<String, Object?>>().toList();
    final unitAirportIds = <String, String>{};
    for (final unit in document.findAllElements('Uni')) {
      final unitUid = _descendant(unit, 'UniUid');
      final airportUid = _descendant(unit, 'AhpUid');
      final unitId = unitUid?.getAttribute('mid');
      final airportId = airportUid?.getAttribute('mid');
      if (unitId != null && airportId != null) {
        unitAirportIds[unitId] = airportId;
      }
    }
    final comms = document.findAllElements('Aha').map((e) => _airportComm(e, region, cycle)).whereType<Map<String, Object?>>().toList()
      ..addAll(document.findAllElements('Fqy').map((e) => _airportFrequency(e, region, cycle, unitAirportIds)).whereType<Map<String, Object?>>());
    final runways = document.findAllElements('Rwy').map((e) => _runway(e, region, cycle)).whereType<Map<String, Object?>>().toList();
    final runwayEnds = document.findAllElements('Rdn').map((e) => _runwayEnd(e, region, cycle)).whereType<Map<String, Object?>>().toList();
    final waypoints = <Map<String, Object?>>[];
    for (final entry in <(String, String)>[('DpnUid', 'FIX'), ('VorUid', 'VOR'), ('NdbUid', 'NDB')]) {
      final tag = entry.$1.substring(0, 3);
      waypoints.addAll(document.findAllElements(tag)
          .map((e) => _waypoint(e, entry.$1, entry.$2, region, cycle))
          .whereType<Map<String, Object?>>());
    }
    final airspaces = document.findAllElements('Ase').map((e) => _airspace(e, region, cycle)).whereType<Map<String, Object?>>().toList();
    final vertices = <Map<String, Object?>>[];
    for (final boundary in document.findAllElements('Abd')) {
      final rawAirspaceId = _descendant(boundary, 'AseUid')?.getAttribute('mid');
      if (rawAirspaceId == null || rawAirspaceId.isEmpty) continue;
      final airspaceId = _scopedId(region, cycle, rawAirspaceId);
      var sequence = 0;
      for (final vertex in boundary.findElements('Avx')) {
        final lat = parseOfmCoordinateOrNull(_text(vertex, 'geoLat'));
        final lon = parseOfmCoordinateOrNull(_text(vertex, 'geoLong'));
        if (lat == null || lon == null) continue;
        vertices.add({
          'airspace_id': airspaceId,
          'sequence': sequence++,
          'code_type': _text(vertex, 'codeType'),
          'lat': lat,
          'lon': lon,
          'arc_lat': parseOfmCoordinateOrNull(_text(vertex, 'geoLatArc')),
          'arc_lon': parseOfmCoordinateOrNull(_text(vertex, 'geoLongArc')),
          'datum': _text(vertex, 'codeDatum'),
        });
      }
    }
    return OfmxImportResult(
      airports: airports,
      airportComms: comms,
      runways: runways,
      runwayEnds: runwayEnds,
      waypoints: waypoints,
      airspaces: airspaces,
      airspaceVertices: vertices,
    );
  }

  static Map<String, Object?>? _airport(XmlElement element, String fallbackRegion, String cycle) {
    final uid = _descendant(element, 'AhpUid');
    final rawId = uid?.getAttribute('mid');
    final code = uid == null ? null : _text(uid, 'codeId');
    final lat = parseOfmCoordinateOrNull(_text(element, 'geoLat'));
    final lon = parseOfmCoordinateOrNull(_text(element, 'geoLong'));
    if (rawId == null || code == null || code.isEmpty || lat == null || lon == null) return null;
    final actualRegion = uid!.getAttribute('region') ?? fallbackRegion;
    final id = _scopedId(actualRegion, cycle, rawId);
    final elevation = double.tryParse(_text(element, 'valElev') ?? '');
    final transition = double.tryParse(_text(element, 'valTransitionAlt') ?? '');
    return {
      'id': id,
      'region': actualRegion,
      'cycle': cycle,
      'code_id': code,
      'icao': _text(element, 'codeIcao'),
      'iata': _text(element, 'codeIata'),
      'gps_code': _text(element, 'codeGps'),
      'name': _text(element, 'txtName'),
      'city': _text(element, 'txtNameCitySer'),
      'type': _text(element, 'codeType'),
      'lat': lat,
      'lon': lon,
      'elevation_ft': ofmAltitudeFeet(elevation, _text(element, 'uomDistVer')),
      'mag_var': double.tryParse(_text(element, 'valMagVar') ?? ''),
      'transition_alt_ft': ofmAltitudeFeet(transition, _text(element, 'uomTransitionAlt')),
      'source': 'OFM',
      'raw_mid': rawId,
    };
  }

  static Map<String, Object?>? _airportComm(XmlElement element, String region, String cycle) {
    final uid = _descendant(element, 'AhaUid');
    final airportUid = uid == null ? null : _descendant(uid, 'AhpUid');
    final rawId = uid?.getAttribute('mid');
    final rawAirportId = airportUid?.getAttribute('mid');
    if (rawId == null || rawAirportId == null) return null;
    return {
      'id': _scopedId(region, cycle, rawId),
      'airport_id': _scopedId(region, cycle, rawAirportId),
      'code_type': _text(uid!, 'codeType'),
      'value': _text(element, 'txtAddress'),
      'remark': _text(element, 'txtRmk'),
      'sequence': int.tryParse(_text(uid, 'noSeq') ?? ''),
    };
  }

  static Map<String, Object?>? _airportFrequency(
    XmlElement element,
    String region,
    String cycle,
    Map<String, String> unitAirportIds,
  ) {
    final uid = _descendant(element, 'FqyUid');
    final unitUid = uid == null ? null : _descendant(uid, 'UniUid');
    final rawId = uid?.getAttribute('mid');
    final rawUnitId = unitUid?.getAttribute('mid');
    final rawAirportId = rawUnitId == null ? null : unitAirportIds[rawUnitId];
    final value = uid == null ? null : _text(uid, 'valFreqTrans');
    if (rawId == null || rawAirportId == null || value == null || value.isEmpty) return null;
    final frequencyUnit = (_text(element, 'uomFreq') ?? '').trim();
    final serviceUid = _descendant(uid!, 'SerUid');
    return {
      'id': _scopedId(region, cycle, rawId),
      'airport_id': _scopedId(region, cycle, rawAirportId),
      'code_type': serviceUid == null ? _text(unitUid!, 'codeType') : _directText(serviceUid, 'codeType'),
      'value': frequencyUnit.isEmpty ? value : '$value $frequencyUnit',
      'remark': _text(element, 'txtCallSign') ?? _text(element, 'txtRmk'),
      'sequence': serviceUid == null ? null : int.tryParse(_directText(serviceUid, 'noSeq') ?? ''),
    };
  }

  static Map<String, Object?>? _runway(XmlElement element, String region, String cycle) {
    final uid = _descendant(element, 'RwyUid');
    final airportUid = uid == null ? null : _descendant(uid, 'AhpUid');
    final rawId = uid?.getAttribute('mid');
    final rawAirportId = airportUid?.getAttribute('mid');
    if (rawId == null || rawAirportId == null) return null;
    return {
      'id': _scopedId(region, cycle, rawId),
      'airport_id': _scopedId(region, cycle, rawAirportId),
      'designation': _text(uid!, 'txtDesig'),
      'length_m': _distanceMeters(_text(element, 'valLen'), _text(element, 'uomDimRwy')),
      'width_m': _distanceMeters(_text(element, 'valWid'), _text(element, 'uomDimRwy')),
      'surface': _text(element, 'codeComposition'),
      'condition': _text(element, 'codeCondSfc'),
      'remark': _text(element, 'txtRmk'),
    };
  }

  static Map<String, Object?>? _runwayEnd(XmlElement element, String region, String cycle) {
    final uid = _descendant(element, 'RdnUid');
    final runwayUid = uid == null ? null : _descendant(uid, 'RwyUid');
    final rawId = uid?.getAttribute('mid');
    final rawRunwayId = runwayUid?.getAttribute('mid');
    if (rawId == null || rawRunwayId == null) return null;
    final tdze = double.tryParse(_text(element, 'valElevTdz') ?? '');
    return {
      'id': _scopedId(region, cycle, rawId),
      'runway_id': _scopedId(region, cycle, rawRunwayId),
      'designation': _directText(uid!, 'txtDesig'),
      'lat': parseOfmCoordinateOrNull(_text(element, 'geoLat')),
      'lon': parseOfmCoordinateOrNull(_text(element, 'geoLong')),
      'true_bearing': double.tryParse(_text(element, 'valTrueBrg') ?? ''),
      'mag_bearing': double.tryParse(_text(element, 'valMagBrg') ?? ''),
      'tdze_ft': ofmAltitudeFeet(tdze, _text(element, 'uomElevTdz')),
      'pattern': _text(element, 'codeVfrPattern'),
      'vasi_type': _text(element, 'codeTypeVasis'),
      'remark': _text(element, 'txtRmk'),
    };
  }

  static Map<String, Object?>? _waypoint(
    XmlElement element,
    String uidName,
    String kind,
    String fallbackRegion,
    String cycle,
  ) {
    final uid = _descendant(element, uidName);
    final rawId = uid?.getAttribute('mid');
    final code = uid == null ? null : _text(uid, 'codeId');
    final lat = uid == null ? null : parseOfmCoordinateOrNull(_text(uid, 'geoLat'));
    final lon = uid == null ? null : parseOfmCoordinateOrNull(_text(uid, 'geoLong'));
    if (rawId == null || code == null || code.isEmpty || lat == null || lon == null) return null;
    final actualRegion = uid!.getAttribute('region') ?? fallbackRegion;
    final frequency = _text(element, 'valFreq');
    final frequencyUnit = _text(element, 'uomFreq');
    final airport = _descendant(element, 'AhpUidAssoc');
    return {
      'id': _scopedId(actualRegion, cycle, rawId),
      'region': actualRegion,
      'cycle': cycle,
      'raw_mid': rawId,
      'code_id': code,
      'kind': kind,
      'type': kind == 'FIX' ? _text(element, 'codeType') : (_text(element, 'codeType') ?? kind),
      'name': _text(element, 'txtName'),
      'lat': lat,
      'lon': lon,
      'frequency': frequency == null
          ? null
          : [frequency, frequencyUnit].where((value) => value != null && value.isNotEmpty).join(' '),
      'mag_var': double.tryParse(_text(element, 'valMagVar') ?? ''),
      'airport_code': airport == null ? null : _text(airport, 'codeId'),
      'remark': _text(element, 'txtRmk'),
    };
  }

  static Map<String, Object?>? _airspace(XmlElement element, String fallbackRegion, String cycle) {
    final uid = _descendant(element, 'AseUid');
    final rawId = uid?.getAttribute('mid');
    if (rawId == null) return null;
    final actualRegion = uid!.getAttribute('region') ?? fallbackRegion;
    final id = _scopedId(actualRegion, cycle, rawId);
    final upper = double.tryParse(_text(element, 'valDistVerUpper') ?? '');
    final lower = double.tryParse(_text(element, 'valDistVerLower') ?? '');
    return {
      'id': id,
      'region': actualRegion,
      'cycle': cycle,
      'code_id': _text(uid, 'codeId'),
      'code_type': _text(uid, 'codeType'),
      'class': _text(element, 'codeClass'),
      'name': _text(element, 'txtName'),
      'alt_upper_code': _text(element, 'codeDistVerUpper'),
      'alt_upper_value': upper,
      'alt_upper_uom': _text(element, 'uomDistVerUpper'),
      'alt_upper_ft': ofmAltitudeFeet(upper, _text(element, 'uomDistVerUpper')),
      'alt_lower_code': _text(element, 'codeDistVerLower'),
      'alt_lower_value': lower,
      'alt_lower_uom': _text(element, 'uomDistVerLower'),
      'alt_lower_ft': ofmAltitudeFeet(lower, _text(element, 'uomDistVerLower')),
      'selectable': _text(element, 'codeSelAvbl'),
      'remark': _text(element, 'txtRmk'),
      'raw_mid': rawId,
    };
  }

  static XmlElement? _descendant(XmlElement element, String name) {
    for (final child in element.descendants.whereType<XmlElement>()) {
      if (child.name.local == name) return child;
    }
    return null;
  }

  static String? _text(XmlElement element, String name) => _descendant(element, name)?.innerText.trim();

  static String? _directText(XmlElement element, String name) {
    for (final child in element.childElements) {
      if (child.name.local == name) return child.innerText.trim();
    }
    return null;
  }

  static String _scopedId(String region, String cycle, String rawId) => '$region:$cycle:$rawId';

  static double? _distanceMeters(String? raw, String? unit) {
    final value = double.tryParse(raw ?? '');
    if (value == null) return null;
    switch ((unit ?? '').toUpperCase()) {
      case 'FT': return value / 3.280839895013123;
      case 'M':
      case '': return value;
      default: return null;
    }
  }
}
