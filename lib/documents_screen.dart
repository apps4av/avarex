import 'package:avaremp/storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:widget_zoom/widget_zoom.dart';

import 'constants.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<StatefulWidget> createState() => DocumentsScreenState();
}



class DocumentsScreenState extends State<DocumentsScreen> {

  String? filter; // for filtering docs

  final List<Document> products = [
    Document("WPC",              "WPC Surface Analysis",   "https://aviationweather.gov/data/products/progs/F000_wpc_sfc.gif"),
    Document("WPC",              "WPC 6HR Prognostic",     "https://aviationweather.gov/data/products/progs/F006_wpc_prog.gif"),
    Document("WPC",              "WPC 12HR Prognostic",    "https://aviationweather.gov/data/products/progs/F012_wpc_prog.gif"),
    Document("WPC",              "WPC 18HR Prognostic",    "https://aviationweather.gov/data/products/progs/F018_wpc_prog.gif"),
    Document("WPC",              "WPC 24HR Prognostic",    "https://aviationweather.gov/data/products/progs/F024_wpc_prog.gif"),
    Document("WPC",              "WPC 30HR Prognostic",    "https://aviationweather.gov/data/products/progs/F030_wpc_prog.gif"),
    Document("WPC",              "WPC 36HR Prognostic",    "https://aviationweather.gov/data/products/progs/F036_wpc_prog.gif"),
    Document("WPC",              "WPC 48HR Prognostic",    "https://aviationweather.gov/data/products/progs/F048_wpc_prog.gif"),
    Document("WPC",              "WPC 60HR Prognostic",    "https://aviationweather.gov/data/products/progs/F060_wpc_prog.gif"),
    Document("WPC",              "WPC 72HR Prognostic",    "https://aviationweather.gov/data/products/progs/F072_wpc_prog.gif"),
    Document("Misc.",            "Radar",                  "https://radar.weather.gov/ridge/standard/CONUS_loop.gif"),
    Document("Misc.",            "SIGMETs",                "https://www.aviationweather.gov/data/products/sigmet/sigmet_all.gif"),
    Document("AIRMET Tango",     "AIRMET Tango 00HR",      "https://www.aviationweather.gov/data/products/gairmet/F00_gairmet_tango_us.gif"),
    Document("AIRMET Tango",     "AIRMET Tango 03HR",      "https://www.aviationweather.gov/data/products/gairmet/F03_gairmet_tango_us.gif"),
    Document("AIRMET Tango",     "AIRMET Tango 06HR",      "https://www.aviationweather.gov/data/products/gairmet/F06_gairmet_tango_us.gif"),
    Document("AIRMET Tango",     "AIRMET Tango 09HR",      "https://www.aviationweather.gov/data/products/gairmet/F09_gairmet_tango_us.gif"),
    Document("AIRMET Tango",     "AIRMET Tango 12HR",      "https://www.aviationweather.gov/data/products/gairmet/F12_gairmet_tango_us.gif"),
    Document("AIRMET Sierra",    "AIRMET Sierra 00HR",     "https://www.aviationweather.gov/data/products/gairmet/F00_gairmet_sierra_us.gif"),
    Document("AIRMET Sierra",    "AIRMET Sierra 03HR",     "https://www.aviationweather.gov/data/products/gairmet/F03_gairmet_sierra_us.gif"),
    Document("AIRMET Sierra",    "AIRMET Sierra 06HR",     "https://www.aviationweather.gov/data/products/gairmet/F06_gairmet_sierra_us.gif"),
    Document("AIRMET Sierra",    "AIRMET Sierra 09HR",     "https://www.aviationweather.gov/data/products/gairmet/F09_gairmet_sierra_us.gif"),
    Document("AIRMET Sierra",    "AIRMET Sierra 12HR",     "https://www.aviationweather.gov/data/products/gairmet/F12_gairmet_sierra_us.gif"),
    Document("AIRMET Zulu",      "AIRMET Zulu 00HR",       "https://www.aviationweather.gov/data/products/gairmet/F00_gairmet_zulu-f_us.gif"),
    Document("AIRMET Zulu",      "AIRMET Zulu 03HR",       "https://www.aviationweather.gov/data/products/gairmet/F03_gairmet_zulu-f_us.gif"),
    Document("AIRMET Zulu",      "AIRMET Zulu 06HR",       "https://www.aviationweather.gov/data/products/gairmet/F06_gairmet_zulu-f_us.gif"),
    Document("AIRMET Zulu",      "AIRMET Zulu 09HR",       "https://www.aviationweather.gov/data/products/gairmet/F09_gairmet_zulu-f_us.gif"),
    Document("AIRMET Zulu",      "AIRMET Zulu 12HR",       "https://www.aviationweather.gov/data/products/gairmet/F12_gairmet_zulu-f_us.gif"),
    Document("Surface Forecast", "Surface Forecast 03H",   "https://www.aviationweather.gov/data/products/gfa/F03_gfa_sfc_us.png"),
    Document("Surface Forecast", "Surface Forecast 06H",   "https://www.aviationweather.gov/data/products/gfa/F06_gfa_sfc_us.png"),
    Document("Surface Forecast", "Surface Forecast 09H",   "https://www.aviationweather.gov/data/products/gfa/F09_gfa_sfc_us.png"),
    Document("Surface Forecast", "Surface Forecast 12H",   "https://www.aviationweather.gov/data/products/gfa/F12_gfa_sfc_us.png"),
    Document("Surface Forecast", "Surface Forecast 15H",   "https://www.aviationweather.gov/data/products/gfa/F15_gfa_sfc_us.png"),
    Document("Surface Forecast", "Surface Forecast 18H",   "https://www.aviationweather.gov/data/products/gfa/F18_gfa_sfc_us.png"),
    Document("Clouds Forecast",  "Clouds Forecast 03H",    "https://www.aviationweather.gov/data/products/gfa/F03_gfa_clouds_us.png"),
    Document("Clouds Forecast",  "Clouds Forecast 06H",    "https://www.aviationweather.gov/data/products/gfa/F06_gfa_clouds_us.png"),
    Document("Clouds Forecast",  "Clouds Forecast 09H",    "https://www.aviationweather.gov/data/products/gfa/F09_gfa_clouds_us.png"),
    Document("Clouds Forecast",  "Clouds Forecast 12H",    "https://www.aviationweather.gov/data/products/gfa/F12_gfa_clouds_us.png"),
    Document("Clouds Forecast",  "Clouds Forecast 15H",    "https://www.aviationweather.gov/data/products/gfa/F15_gfa_clouds_us.png"),
    Document("Clouds Forecast",  "Clouds Forecast 18H",    "https://www.aviationweather.gov/data/products/gfa/F18_gfa_clouds_us.png"),
    Document("Winds/Temp",       "Winds/Temp 5000 06HR",   "https://aviationweather.gov/data/products/fax/F06_wind_050_b1.gif"),
    Document("Winds/Temp",       "Winds/Temp 10000 06HR",  "https://aviationweather.gov/data/products/fax/F06_wind_100_b1.gif"),
    Document("Winds/Temp",       "Winds/Temp 18000 06HR",  "https://aviationweather.gov/data/products/fax/F06_wind_180_b1.gif"),
    Document("Winds/Temp",       "Winds/Temp 24000 06HR",  "https://aviationweather.gov/data/products/fax/F06_wind_240_b1.gif"),
    Document("Winds/Temp",       "Winds/Temp 30000 06HR",  "https://aviationweather.gov/data/products/fax/F06_wind_300_b1.gif"),
    Document("Winds/Temp",       "Winds/Temp 5000 12HR",   "https://aviationweather.gov/data/products/fax/F12_wind_050_b1.gif"),
    Document("Winds/Temp",       "Winds/Temp 10000 12HR",  "https://aviationweather.gov/data/products/fax/F12_wind_100_b1.gif"),
    Document("Winds/Temp",       "Winds/Temp 18000 12HR",  "https://aviationweather.gov/data/products/fax/F12_wind_180_b1.gif"),
    Document("Winds/Temp",       "Winds/Temp 24000 12HR",  "https://aviationweather.gov/data/products/fax/F12_wind_240_b1.gif"),
    Document("Winds/Temp",       "Winds/Temp 30000 12HR",  "https://aviationweather.gov/data/products/fax/F12_wind_300_b1.gif"),
  ];

  //if you don't want widget full screen then use center widget
  Widget smallImage(String name, String url) {
     Widget widget = WidgetZoom(
        heroAnimationTag: name,
        zoomWidget: CachedNetworkImage(
          imageUrl: url,
          cacheManager: FileCacheManager().networkCacheManager,));

    return Padding(padding: const EdgeInsets.fromLTRB(10, 0, 0, 10),
      child: Center(
          child: Column(
              children: [
                SizedBox(width: 256, height: 128, child: widget),
                Text(name),
              ]
          )),
    );
  }


  @override
  Widget build(BuildContext context) {
    List<String> ctypes = products.map((e) => e.type).toSet().toList(); // toSet for unique.
    ctypes.insert(0, "All Documents"); // everything shows
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Documents"),
          actions: [
            Padding(padding: const EdgeInsets.fromLTRB(0, 0, 10, 0), child:
              DropdownButtonHideUnderline(child:
                DropdownButton2<String>( // airport selection
                  buttonStyleData: ButtonStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Constants.dropDownButtonBackgroundColor),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                  ),
                  isExpanded: false,
                  value: filter ?? ctypes[0],
                  items: ctypes.map((String e) => DropdownMenuItem<String>(value: e, child: Text(e, style: TextStyle(fontSize: Constants.dropDownButtonFontSize)))).toList(),
                  onChanged: (value) {
                    setState(() {
                      filter = value ?? ctypes[0];
                    });
                  },
                )
              )
            )
          ]
      ),
      body: SingleChildScrollView(
          child: GridView.count(
            primary: false,
            shrinkWrap: true,
            crossAxisCount: 2,
            children: <Widget>[
              for(Document p in products)
                if(filter != null ? p.type == filter || filter == ctypes[0] : true)
                  smallImage(p.name, p.url),
            ],
          ),
      ),
    );
  }
}


class Document {
  String name;
  String url;
  String type;
  Document(this.type, this.name, this.url);
}

