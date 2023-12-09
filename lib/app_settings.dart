
import 'package:avaremp/chart.dart';
import 'package:avaremp/settings_cache_provider.dart';
import 'package:flutter_settings_screen_ex/flutter_settings_screen_ex.dart';

class AppSettings {

  Future<void> initSettings() async {
    await Settings.init(
      cacheProvider: SettingsCacheProvider(),
    );
  }

  void setChartType(String chart) {
    Settings.setValue("key-chart", chart);
  }

  String getChartType() {
    return Settings.getValue("key-chart", defaultValue: ChartCategory.sectional) as String;
  }

  bool getSimulationMode() {
    return Settings.getValue("key-simulation", defaultValue: false) as bool;
  }

  bool getTracks() {
    return Settings.getValue("key-tracks", defaultValue: false) as bool;
  }

  bool getDarkMode() {
    return Settings.getValue("key-dark-mode", defaultValue: true) as bool;
  }

}
