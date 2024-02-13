import 'package:avaremp/storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:widget_zoom/widget_zoom.dart';

import 'constants.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});
  @override
  State<StatefulWidget> createState() => DocumentsScreenState();
}


class Product {
  String name;
  String url;
  Product(this.name, this.url);
}

class DocumentsScreenState extends State<DocumentsScreen> {

  final List<Product> products = [
    Product("WPC Surface Analysis",   "https://aviationweather.gov/data/products/progs/F000_wpc_sfc.gif"),
    Product("WPC 6HR Prognostic",     "https://aviationweather.gov/data/products/progs/F006_wpc_prog.gif"),
    Product("WPC 12HR Prognostic",    "https://aviationweather.gov/data/products/progs/F012_wpc_prog.gif"),
    Product("WPC 18HR Prognostic",    "https://aviationweather.gov/data/products/progs/F018_wpc_prog.gif"),
    Product("WPC 24HR Prognostic",    "https://aviationweather.gov/data/products/progs/F024_wpc_prog.gif"),
    Product("WPC 30HR Prognostic",    "https://aviationweather.gov/data/products/progs/F030_wpc_prog.gif"),
    Product("WPC 36HR Prognostic",    "https://aviationweather.gov/data/products/progs/F036_wpc_prog.gif"),
    Product("WPC 48HR Prognostic",    "https://aviationweather.gov/data/products/progs/F048_wpc_prog.gif"),
    Product("WPC 60HR Prognostic",    "https://aviationweather.gov/data/products/progs/F060_wpc_prog.gif"),
    Product("WPC 72HR Prognostic",    "https://aviationweather.gov/data/products/progs/F072_wpc_prog.gif"),
    Product("Radar",                  "https://radar.weather.gov/ridge/standard/CONUS_loop.gif"),
    Product("SIGMETs",                "https://www.aviationweather.gov/data/products/sigmet/sigmet_all.gif"),
    Product("AIRMET Tango 00HR",      "https://www.aviationweather.gov/data/products/gairmet/F00_gairmet_tango_us.gif"),
    Product("AIRMET Tango 03HR",      "https://www.aviationweather.gov/data/products/gairmet/F03_gairmet_tango_us.gif"),
    Product("AIRMET Tango 06HR",      "https://www.aviationweather.gov/data/products/gairmet/F06_gairmet_tango_us.gif"),
    Product("AIRMET Tango 09HR",      "https://www.aviationweather.gov/data/products/gairmet/F09_gairmet_tango_us.gif"),
    Product("AIRMET Tango 12HR",      "https://www.aviationweather.gov/data/products/gairmet/F12_gairmet_tango_us.gif"),
    Product("AIRMET Sierra 00HR",     "https://www.aviationweather.gov/data/products/gairmet/F00_gairmet_sierra_us.gif"),
    Product("AIRMET Sierra 03HR",     "https://www.aviationweather.gov/data/products/gairmet/F03_gairmet_sierra_us.gif"),
    Product("AIRMET Sierra 06HR",     "https://www.aviationweather.gov/data/products/gairmet/F06_gairmet_sierra_us.gif"),
    Product("AIRMET Sierra 09HR",     "https://www.aviationweather.gov/data/products/gairmet/F09_gairmet_sierra_us.gif"),
    Product("AIRMET Sierra 12HR",     "https://www.aviationweather.gov/data/products/gairmet/F12_gairmet_sierra_us.gif"),
    Product("AIRMET Zulu 00HR",       "https://www.aviationweather.gov/data/products/gairmet/F00_gairmet_zulu-f_us.gif"),
    Product("AIRMET Zulu 03HR",       "https://www.aviationweather.gov/data/products/gairmet/F03_gairmet_zulu-f_us.gif"),
    Product("AIRMET Zulu 06HR",       "https://www.aviationweather.gov/data/products/gairmet/F06_gairmet_zulu-f_us.gif"),
    Product("AIRMET Zulu 09HR",       "https://www.aviationweather.gov/data/products/gairmet/F09_gairmet_zulu-f_us.gif"),
    Product("AIRMET Zulu 12HR",       "https://www.aviationweather.gov/data/products/gairmet/F12_gairmet_zulu-f_us.gif"),
    Product("Surface Forecast 03H",   "https://www.aviationweather.gov/data/products/gfa/F03_gfa_sfc_us.png"),
    Product("Surface Forecast 06H",   "https://www.aviationweather.gov/data/products/gfa/F06_gfa_sfc_us.png"),
    Product("Surface Forecast 09H",   "https://www.aviationweather.gov/data/products/gfa/F09_gfa_sfc_us.png"),
    Product("Surface Forecast 12H",   "https://www.aviationweather.gov/data/products/gfa/F12_gfa_sfc_us.png"),
    Product("Surface Forecast 15H",   "https://www.aviationweather.gov/data/products/gfa/F15_gfa_sfc_us.png"),
    Product("Surface Forecast 18H",   "https://www.aviationweather.gov/data/products/gfa/F18_gfa_sfc_us.png"),
    Product("Clouds Forecast 03H",    "https://www.aviationweather.gov/data/products/gfa/F03_gfa_clouds_us.png"),
    Product("Clouds Forecast 06H",    "https://www.aviationweather.gov/data/products/gfa/F06_gfa_clouds_us.png"),
    Product("Clouds Forecast 09H",    "https://www.aviationweather.gov/data/products/gfa/F09_gfa_clouds_us.png"),
    Product("Clouds Forecast 12H",    "https://www.aviationweather.gov/data/products/gfa/F12_gfa_clouds_us.png"),
    Product("Clouds Forecast 15H",    "https://www.aviationweather.gov/data/products/gfa/F15_gfa_clouds_us.png"),
    Product("Clouds Forecast 18H",    "https://www.aviationweather.gov/data/products/gfa/F18_gfa_clouds_us.png"),
  ];

  //if you don't want widget full screen then use center widget
  Widget smallImage(String name, String url) => Padding(padding: const EdgeInsets.fromLTRB(10, 0, 0, 10),
    child: Center(
            child:Column(
              children:[
                SizedBox(width: 256, height: 128, child: WidgetZoom(heroAnimationTag: name, zoomWidget:
                CachedNetworkImage(imageUrl: url, cacheManager: FileCacheManager().networkCacheManager,))),
                Text(name),
            ]
          )),

  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Documents"),
      ),
      body: SingleChildScrollView(
          child: GridView.count(
                primary: false,
                shrinkWrap: true,
                crossAxisCount: 2,
                children: <Widget>[
                  for(Product p in products)
                    smallImage(p.name, p.url),

                ],
              ),
        ),
    );
  }
}

