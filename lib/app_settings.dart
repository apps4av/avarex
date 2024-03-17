
import 'package:avaremp/chart.dart';
import 'package:avaremp/documents_screen.dart';
import 'package:avaremp/settings_cache_provider.dart';
import 'package:flutter_settings_screen_ex/flutter_settings_screen_ex.dart';

class AppSettings {

  Future<void> initSettings() async {
    await Settings.init(
      cacheProvider: SettingsCacheProvider(),
    );
  }

  void setChartType(String chart) {
    Settings.setValue("key-chart-v1", chart);
  }

  String getChartType() {
    return Settings.getValue("key-chart-v1", defaultValue: ChartCategory.sectional) as String;
  }

  bool getNorthUp() {
    return Settings.getValue("key-north-up", defaultValue: true) as bool;
  }

  void setNorthUp(bool northUp) {
    Settings.setValue("key-north-up", northUp);
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
    Settings.setValue("key-instruments-v8", instruments);
  }

  String getInstruments() {
    return Settings.getValue("key-instruments-v8", defaultValue: "GS,ALT,MH,NXT,DIS,BRG,UPT,UTC,SRC") as String;
  }

  List<String> getLayers() {
    return (Settings.getValue("key-layers-v29", defaultValue: "Nav,Chart,OSM,Weather,TFR,Plate,Traffic,PFD,Tracks") as String).split(",");
  }

  List<bool> getLayersState() {
    return (Settings.getValue("key-layers-state-v29", defaultValue: "true,true,true,false,true,false,true,false,false") as String).split(",").map((String e) => e == 'true' ? true : false).toList();
  }

  void setLayersState(List<bool> state) {
    Settings.setValue("key-layers-state-v29", state.map((bool e) => e.toString()).toList().join(","));
  }

  void setCurrentPlateAirport(String name) {
    Settings.setValue("key-current-plate-airport", name);
  }

  String getCurrentPlateAirport() {
    return Settings.getValue("key-current-plate-airport", defaultValue: "") as String;
  }

  int getTas() {
    return Settings.getValue("key-airplane-tas-v2", defaultValue: 100) as int;
  }

  void setTas(int value) {
    Settings.setValue("key-airplane-tas-v2", value);
  }

  int getFuelBurn() {
    return Settings.getValue("key-airplane-fuel-burn-v2", defaultValue: 10) as int;
  }

  void setFuelBurn(int value) {
    Settings.setValue("key-airplane-fuel-burn-v2", value);
  }

  bool isSigned() {
    return Settings.getValue("key-signed", defaultValue: false) as bool;
  }

  void setSign(bool value) {
    Settings.setValue("key-signed", value);
  }

  bool showIntro() {
    return Settings.getValue("key-intro", defaultValue: true) as bool;
  }

  void setIntro(bool value) {
    Settings.setValue("key-intro", value);
  }

  void setDocumentPage(String name) {
    Settings.setValue("key-document-page-v1", name);
  }

  String getDocumentPage() {
    return Settings.getValue("key-document-page-v1", defaultValue: DocumentsScreen.allDocuments) as String;
  }

  bool isAudibleAlertsEnabled() {
    return Settings.getValue("key-audible-alerts", defaultValue: true) as bool;
  }

  void setAudibleAlertsEnabled(bool value) {
    Settings.setValue("key-audible-alerts", value);
  } 

}
