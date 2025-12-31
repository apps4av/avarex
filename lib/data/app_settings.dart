import 'package:avaremp/chart.dart';
import 'package:avaremp/documents_screen.dart';
import 'package:avaremp/data/settings_cache_provider.dart';

class AppSettings {

  late final SettingsCacheProvider provider;
  // local vars, to prevent constant cache lookups that are showing up in CPU flamechart
  bool _localAudibleAlertsEnabledSetting = true;  
  String _localUnits = "Maritime";

  Future<void> initSettings() async {
    provider = SettingsCacheProvider();
    await provider.init();
    _localAudibleAlertsEnabledSetting = provider.getValue("key-audible-alerts", defaultValue: _localAudibleAlertsEnabledSetting) as bool;
    _localUnits = provider.getValue("key-units", defaultValue: _localUnits) as String;
  }

  void setChartType(String chart) {
    provider.setString("key-chart-v1", chart);
  }

  String getChartType() {
    return provider.getValue("key-chart-v1", defaultValue: ChartCategory.sectional) as String;
  }

  bool getNorthUp() {
    return provider.getValue("key-north-up", defaultValue: true) as bool;
  }

  void setNorthUp(bool northUp) {
    provider.setBool("key-north-up", northUp);
  }

  bool isRubberBanding() {
    return provider.getValue("key-rubber-banding", defaultValue: false) as bool;
  }

  void setRubberBanding(bool value) {
    provider.setBool("key-rubber-banding", value);
  }

  bool isLightMode() {
    return provider.getValue("key-light-mode", defaultValue: false) as bool;
  }

  void setLightMode(bool lightMode) {
    provider.setBool("key-light-mode", lightMode);
  }

  void setZoom(double zoom) {
    provider.setDouble("key-chart-zoom", zoom);
  }

  double getZoom() {
    return provider.getValue("key-chart-zoom", defaultValue: 0.0) as double;
  }

  void setRotation(double rotation) {
    provider.setDouble("key-chart-rotation", rotation);
  }

  double getRotation() {
    return provider.getValue("key-chart-rotation", defaultValue: 0.0) as double;
  }

  void setCenterLatitude(double l) {
    provider.setDouble("key-chart-center-latitude", l);
  }

  double getCenterLatitude() {
    return provider.getValue("key-chart-center-latitude", defaultValue: 37.0) as double;
  }

  void setCenterLongitude(double l) {
    provider.setDouble("key-chart-center-longitude", l);
  }

  double getCenterLongitude() {
    return provider.getValue("key-chart-center-longitude", defaultValue: -95.0) as double;
  }

  void setInstruments(String instruments) {
    provider.setString("key-instruments-v16", instruments);
  }

  String getInstruments() {
    return provider.getValue("key-instruments-v16", defaultValue: "GS,ALT,MT,PRV,NXT,DIS,BRG,GEL,ETA,ETE,VSR,UPT,DNT,UTC,SRC,FLT") as String;
  }

  void setUnits(String units) {
    provider.setString("key-units", units);
    _localUnits = units;
  }

  String getUnits() {
    return _localUnits; // Due to number of times called, using local/memory var results in significant CPU relief
  }

  List<String> getLayers() {
    return (provider.getValue("key-layers-v42", defaultValue: "Nav,Circles,Chart,OSM,OpenAIP,Topo,Elevation,Weather,Radar,TFR,Plate,Traffic,Obstacles,Tape,GeoJSON,PFD,Tracks") as String).split(",");
  }

  List<double> getLayersOpacity() {
    return (provider.getValue("key-layers-opacity-v42", defaultValue: "1,0,1,1,0,0,0,0,0,1,0,1,0,0,0,0,0") as String).split(",").map((String e) => double.parse(e)).toList();
  }

  void setLayersOpacity(List<double> opacity) {
    provider.setString("key-layers-opacity-v42", opacity.map((double e) => e.toString()).toList().join(","));
  }

  void setCurrentPlateAirport(String name) {
    provider.setString("key-current-plate-airport", name);
  }

  String getCurrentPlateAirport() {
    return provider.getValue("key-current-plate-airport", defaultValue: "") as String;
  }

  void setEmail(String name) {
    provider.setString("key-user-email", name);
  }

  String getEmail() {
    return provider.getValue("key-user-email", defaultValue: "") as String;
  }

  void setLastRouteEntry(String value) {
    provider.setString("key-last-route-entry", value);
  }

  String getLastRouteEntry() {
    return provider.getValue("key-last-route-entry", defaultValue: "") as String;
  }

  void setAircraft(String name) {
    provider.setString("key-user-aircraft", name);
  }

  String getAircraft() {
    return provider.getValue("key-user-aircraft", defaultValue: "") as String;
  }

  void setWnb(String name) {
    provider.setString("key-user-wnb", name);
  }

  String getWnb() {
    return provider.getValue("key-user-wnb", defaultValue: "") as String;
  }

  void setChecklist(String name) {
    provider.setString("key-user-checklist", name);
  }

  String getChecklist() {
    return provider.getValue("key-user-checklist", defaultValue: "") as String;
  }

  double getTas() {
    return provider.getValue("key-airplane-tas-v3", defaultValue: 100.0) as double;
  }

  void setTas(double value) {
    provider.setDouble("key-airplane-tas-v3", value);
  }

  double getFuelBurn() {
    return provider.getValue("key-airplane-fuel-burn-v3", defaultValue: 10.0) as double;
  }

  void setFuelBurn(double value) {
    provider.setDouble("key-airplane-fuel-burn-v3", value);
  }

  bool isSigned() {
    return provider.getValue("key-signed", defaultValue: false) as bool;
  }

  void setSign(bool value) {
    provider.setBool("key-signed", value);
  }

  String getTrafficPuckSize() {
    return provider.getValue("key-traffic-puck-size", defaultValue: "S") as String;
  }

  void setTrafficPuckSize(String value) {
    provider.setString("key-traffic-puck-size", value);
  }

  bool showIntro() {
    return provider.getValue("key-intro", defaultValue: true) as bool;
  }

  void setIntro(bool value) {
    provider.setBool("key-intro", value);
  }

  void setDocumentPage(String name) {
    provider.setString("key-document-page-v1", name);
  }

  String getDocumentPage() {
    return provider.getValue("key-document-page-v1", defaultValue: DocumentsScreen.allDocuments) as String;
  }

  bool isAudibleAlertsEnabled() { 
    return _localAudibleAlertsEnabledSetting; // Due to number of times called, using local/memory var results in significant CPU relief
  }

  void setAudibleAlertsEnabled(bool value) {
    provider.setBool("key-audible-alerts", value);
    _localAudibleAlertsEnabledSetting = value;
  }

  bool isInstrumentsVisiblePlate() {
    return provider.getValue("key-enable-instruments-plate", defaultValue: true) as bool;
  }

  void setInstrumentsVisiblePlate(bool value) {
    provider.setBool("key-enable-instruments-plate", value);
  }

  double getInstrumentScaleFactor() {
    return provider.getValue("key-instrument-scale-factor", defaultValue: 1.0) as double;
  }

  void setInstrumentScaleFactor(double value) {
    // limit 2x
    if(value > 2.0) {
      value = 2.0;
    }
    if(value < 0.5) {
      value = 0.5;
    }
    provider.setDouble("key-instrument-scale-factor", value);
  }

  bool shouldShowReview() {
    bool show = false;
    // show every 20th time if never not set
    if(provider.getValue("key-review-never", defaultValue: false) as bool) {
      return show;
    }
    int msNow = DateTime.now().millisecondsSinceEpoch;
    int ms = provider.getValue("key-review-last-ask", defaultValue: msNow) as int;
    if(ms == msNow) {
      // first time run
      provider.setInt("key-review-last-ask", msNow);
    }
    // show every 7 days
    else if((msNow - ms) > 1000 * 60 * 60 * 24 * 7) {
      provider.setInt("key-review-last-ask", msNow);
      show = true;
    }
    return show;
  }

  void doneReview() {
    provider.setBool("key-review-never", true);
  }

}