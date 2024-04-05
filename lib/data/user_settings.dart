import 'package:realm/realm.dart';


part 'user_settings.realm.dart';

@RealmModel()
class _UserSettings {
  @PrimaryKey()
  @MapTo('_id')
  late ObjectId id;

  late String key;
  late String value;
}

