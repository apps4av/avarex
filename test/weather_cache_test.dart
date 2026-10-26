import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cache extends WeatherCache {
  int downloads = 0;

  _Cache() : super(const [], _none);

  static Future<List<Weather>> _none() async => [];

  @override
  Future<void> download([String? argument]) async {
    downloads++;
  }
}

void main() {
  test("an expired forecast stays available while it refreshes", () async {
    final _Cache cache = _Cache();
    await Future<void>.delayed(Duration.zero);
    final Weather expired = Weather(
      "BOS06H",
      DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      DateTime.now().toUtc(),
      Weather.sourceInternet,
    );
    cache.put(expired);

    expect(cache.get("BOS06H"), same(expired));
    expect(cache.downloads, 1);
    expect(cache.get("BOS06H"), same(expired));
    expect(cache.downloads, 1);
    expect(cache.get("missing"), isNull);
  });
}
