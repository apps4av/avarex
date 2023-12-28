
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

  bool getNorthUp() {
    return Settings.getValue("key-north-up", defaultValue: true) as bool;
  }

  void setZoom(double zoom) {
    Settings.setValue("key-chart-zoom", zoom);
  }

  double getZoom() {
    return Settings.getValue("key-chart-zoom", defaultValue: 0.0) as double;
  }

  void setRotation(double rotation) {
    Settings.setValue("key-chart-rotation", rotation);
  }

  double getRotation() {
    return Settings.getValue("key-chart-rotation", defaultValue: 0.0) as double;
  }

  void setCenterLatitude(double l) {
    Settings.setValue("key-chart-center-latitude", l);
  }

  double getCenterLatitude() {
    return Settings.getValue("key-chart-center-latitude", defaultValue: 37.0) as double;
  }

  void setCenterLongitude(double l) {
    Settings.setValue("key-chart-center-longitude", l);
  }

  double getCenterLongitude() {
    return Settings.getValue("key-chart-center-longitude", defaultValue: -95.0) as double;
  }

  void setInstruments(String instruments) {
    Settings.setValue("key-instruments-v1", instruments);
  }

  String getInstruments() {
    return Settings.getValue("key-instruments-v3", defaultValue: "Gnd Speed,Alt,Track,Dest.,Distance,Bearing,Up Timer,UTC") as String;
  }

  void setCurrentPlateAirport(String name) {
    Settings.setValue("key-current-plate-airport", name);
  }

  String getCurrentPlateAirport() {
    return Settings.getValue("key-current-plate-airport", defaultValue: "") as String;
  }


}
