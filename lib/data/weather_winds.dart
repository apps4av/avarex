import 'package:realm/realm.dart';


part 'weather_winds.realm.dart';

@RealmModel()
class _WeatherWinds {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String station;
  late int utcMs;
  late String w0k;
  late String w3k;
  late String w6k;
  late String w9k;
  late String w12k;
  late String w18k;
  late String w24k;
  late String w30k;
  late String w34k;
  late String w39k;

}
