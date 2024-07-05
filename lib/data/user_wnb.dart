import 'package:realm/realm.dart';


part 'user_wnb.realm.dart';

@RealmModel()
class _UserWnb {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;
  @MapTo('owner_id')
  late String ownerId;
  late String name;
  late String aircraft;
  late String items;
  late double minX;
  late double minY;
  late double maxX;
  late double maxY;
  late String points;
}

