import 'package:realm/realm.dart';


part 'weather_notam.realm.dart';

@RealmModel()
class _WeatherNotam {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String station;
  late String text;
  late int utcMs;
}

