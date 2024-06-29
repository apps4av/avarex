import 'package:realm/realm.dart';


part 'weather_taf.realm.dart';

@RealmModel()
class _WeatherTaf {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String station;
  late String raw;
  late int utcMs;
  late double ARPLatitude;
  late double ARPLongitude;
}
