import 'package:realm/realm.dart';


part 'weather_metar.realm.dart';

@RealmModel()
class _WeatherMetar {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String station;
  late String raw;
  late int utcMs;
  late String category;
  late double ARPLatitude;
  late double ARPLongitude;
}
