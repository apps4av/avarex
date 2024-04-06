import 'package:realm/realm.dart';


part 'user_settings.realm.dart';

@RealmModel()
class _UserSettings {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;
  @MapTo('owner_id')
  late String ownerId;
  late String key;
  late String value;
}

