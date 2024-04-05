import 'package:realm/realm.dart';


part 'user_aircraft.realm.dart';

@RealmModel()
class _UserAircraft {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String tail;
  late String type;
  late String wake;
  late String icao;
  late String equipment;
  late String cruiseTas;
  late String surveillance;
  late String fuelEndurance;
  late String color;
  late String pic;
  late String picInfo;
  late String sinkRate;
  late String fuelBurn;
  late String base;
  late String other;
}

