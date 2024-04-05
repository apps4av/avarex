import 'package:realm/realm.dart';


part 'weather_airep.realm.dart';

@RealmModel()
class _WeatherAirep {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String station;
  late String raw;
  late int utcMs;
  late String coordinates;
}

