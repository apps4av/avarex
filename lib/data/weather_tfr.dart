import 'package:realm/realm.dart';

part 'weather_tfr.realm.dart';

@RealmModel()
class _WeatherTfr {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String station;
  late String coordinates;
  late int utcMs;
  late String upperAltitude;
  late String lowerAltitude;
  late int msEffective;
  late int msExpires;
}

