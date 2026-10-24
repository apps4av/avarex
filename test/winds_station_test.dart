import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/unit_conversion.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  setUp(() {
    Storage().units = UnitConversion("Nautical");
  });

  test("nearest winds station is the field the point sits on", () {
    expect(WindsCache.locateNearestStation(const LatLng(42.36, -71.01)), "BOS");
    expect(WindsCache.locateNearestStation(const LatLng(34.43, -119.84)), "SBA");
    expect(WindsCache.locateNearestStation(const LatLng(51.88, -176.64)), "ADK");
  });
}
