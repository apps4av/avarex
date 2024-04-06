import 'package:realm/realm.dart';


part 'user_plan.realm.dart';

@RealmModel()
class _UserPlan {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;
  @MapTo('owner_id')
  late String ownerId;
  late String name;
  late String route;
}

