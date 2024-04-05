import 'package:realm/realm.dart';


part 'user_recent.realm.dart';

@RealmModel()
class _UserRecent {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String locationID;
  late String facilityName;
  late String type;
  late double latitude;
  late double longitude;
}

