import 'package:avaremp/data/user_settings.dart';
import 'package:realm/realm.dart';

class UserSettingsRealmHelper {
  Realm? _realm;

  Future<void> init()  {
    Configuration config = Configuration.local([UserSettings.schema]);
    _realm = Realm(config);
    return Future.value();
  }

  void insertSetting(String key, String? value) {

    // remove for duplicates
    deleteSetting(key);

    if(null == value) {
      return;
    }
    UserSettings setting = UserSettings(ObjectId(), "", key, value);

    if(null == _realm) {
      return;
    }

    _realm!.write(() {
      _realm!.add(setting);
    });

  }

  String? getSetting(String key) {
    if(null == _realm) {
      return null;
    }

    RealmResults<UserSettings> settings = _realm!.all<UserSettings>().query("key = '$key'");

    if(settings.isEmpty) {
      return null;
    }
    UserSettings? s = settings.first;
    return s.value;
  }

  void deleteSetting(String key) {
    if(null == _realm) {
      return;
    }

    RealmResults<UserSettings> settings = _realm!.all<UserSettings>().query("key = '$key'");

    try {
      _realm!.write(() {
        _realm!.delete(settings.first);
      });
    } catch(e) {}

  }

  void deleteAllSettings() {

    if(null == _realm) {
      return;
    }

    try {
      _realm!.write(() {
        _realm!.deleteAll<UserSettings>();
      });
    } catch(e) {}
  }

  List<Map<String, dynamic>> getAllSettings() {
    List<Map<String, dynamic>> ret = [];

    if(null == _realm) {
      return ret;
    }

    RealmResults<UserSettings> settings = _realm!.all<UserSettings>();

    for(UserSettings setting in settings) {
      ret.add({"key": setting.key, "value": setting.value});
    }
    return ret;
  }

}