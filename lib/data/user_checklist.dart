import 'package:realm/realm.dart';


part 'user_checklist.realm.dart';

@RealmModel()
class _UserChecklist {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;
  @MapTo('owner_id')
  late String ownerId;
  late String name;
  late String aircraft;
  late String steps;
}

