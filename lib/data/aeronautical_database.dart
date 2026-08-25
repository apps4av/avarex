import 'package:latlong2/latlong.dart';

import '../destination/destination.dart';
import '../storage.dart';
import 'main_database_helper.dart';
import '../ofm/ofm_data_provider.dart';
import '../openaip/openaip_database.dart';

class AeronauticalDatabase {
  AeronauticalDatabase._();

  static final AeronauticalDatabase instance = AeronauticalDatabase._();

  OfmDataProvider get _ofm => OfmDataProvider(dataDir: Storage().dataDir);

  Future<OpenAipDatabase> get _openAip async =>
      OpenAipDatabase(database: await OpenAipDatabase.open(Storage().dataDir));

  Future<List<Destination>> findDestinations(String match, {bool exact = false}) async {
    final faa = await MainDatabaseHelper.db.findDestinations(match, exact: exact);
    List<Destination> ofm = const [];
    try {
      ofm = await _ofm.findDestinations(match, exact: exact);
    } catch (_) {
      // OFM is optional; FAA search remains available before any region is installed.
    }
    List<Destination> openAip = const [];
    try {
      openAip = await (await _openAip).findDestinations(match, exact: exact);
    } catch (_) {
      // openAIP is optional.
    }
    final results = <Destination>[...faa];
    final keys = faa.map((d) => '${d.source}:${d.locationID}:${d.type}').toSet();
    for (final item in ofm) {
      if (keys.add('${item.source}:${item.locationID}:${item.type}')) results.add(item);
    }
    for (final item in openAip) {
      if (keys.add('${item.source}:${item.locationID}:${item.type}')) results.add(item);
    }
    return results;
  }

  Future<List<Destination>> findNear(LatLng point, {double factor = 0.001}) async {
    final faa = await MainDatabaseHelper.db.findNear(point, factor: factor);
    List<Destination> ofm = const [];
    try {
      ofm = await _ofm.findNear(point, factor: factor);
    } catch (_) {
      // OFM is optional.
    }
    List<Destination> openAip = const [];
    try {
      openAip = await (await _openAip).findNear(point, factor: factor);
    } catch (_) {
      // openAIP is optional.
    }
    final gps = faa.where((d) => Destination.isGps(d.type)).toList();
    return [...faa.where((d) => !Destination.isGps(d.type)), ...ofm, ...openAip, ...gps];
  }

  Future<List<Destination>> findNearestAirportsWithRunways(
    LatLng point,
    int runwayLengthFeet,
  ) async {
    final faa = await MainDatabaseHelper.db.findNearestAirportsWithRunways(point, runwayLengthFeet);
    List<Destination> ofm = const [];
    try {
      ofm = await _ofm.findNearestAirportsWithRunways(point, runwayLengthFeet);
    } catch (_) {
      // OFM is optional.
    }
    List<Destination> openAip = const [];
    try {
      openAip = await (await _openAip).findNearestAirportsWithRunways(point, runwayLengthFeet);
    } catch (_) {
      // openAIP is optional.
    }
    final results = [...faa, ...ofm, ...openAip];
    results.sort((a, b) {
      final da = const Distance()(point, a.coordinate);
      final db = const Distance()(point, b.coordinate);
      return da.compareTo(db);
    });
    return results;
  }

  Future<List<NavDestination>> findNearestVOR(LatLng point) async {
    final faa = await MainDatabaseHelper.db.findNearestVOR(point);
    List<NavDestination> ofm = const [];
    try {
      ofm = await _ofm.findNearestVOR(point);
    } catch (_) {
      // OFM is optional.
    }
    List<NavDestination> openAip = const [];
    try {
      openAip = await (await _openAip).findNearestVOR(point);
    } catch (_) {
      // openAIP is optional.
    }
    final results = [...faa, ...ofm, ...openAip];
    results.sort((a, b) => const Distance()(point, a.coordinate)
        .compareTo(const Distance()(point, b.coordinate)));
    return results.take(3).toList();
  }

  Future<AirportDestination?> findOfmAirport(String code) async {
    try {
      return await _ofm.findAirport(code);
    } catch (_) {
      return null;
    }
  }

  Future<AirportDestination?> findAirport(String code, {String? source}) async {
    if (source == 'OFM') return findOfmAirport(code);
    if (source == 'openAIP') {
      try {
        return await (await _openAip).findAirport(code);
      } catch (_) {
        return null;
      }
    }
    final faa = await MainDatabaseHelper.db.findAirport(code);
    if (faa != null) return faa;
    final ofm = await findOfmAirport(code);
    if (ofm != null) return ofm;
    try {
      return await (await _openAip).findAirport(code);
    } catch (_) {
      return null;
    }
  }

  Future<List<LatLng>> findObstacles(LatLng point, double minimumMslFeet) async {
    final faa = await MainDatabaseHelper.db.findObstacles(point, minimumMslFeet);
    List<LatLng> openAip = const [];
    try {
      openAip = await (await _openAip).findObstacles(
        latitude: point.latitude,
        longitude: point.longitude,
        minimumMslFeet: minimumMslFeet,
      );
    } catch (_) {
      // openAIP is optional.
    }
    return [...faa, ...openAip];
  }
}
