import 'package:realm/realm.dart';


part 'weather_airsigmet.realm.dart';

@RealmModel()
class _WeatherAirSigmet {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String station;
  late String text;
  late int utcMs;
  late String raw;
  late String coordinates;
  late String hazard;
  late String severity;
  late String type;
}

