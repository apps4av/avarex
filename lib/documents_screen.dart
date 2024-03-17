import 'dart:io';

import 'package:avaremp/path_utils.dart';
import 'package:avaremp/pdf_viewer.dart';
import 'package:avaremp/storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:widget_zoom/widget_zoom.dart';

import 'constants.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  static const String allDocuments = "All Documents";
  static const String userDocuments = "User Docs";

  @override
  State<StatefulWidget> createState() => DocumentsScreenState();
}


class DocumentsScreenState extends State<DocumentsScreen> {

  List<Document> products = [];
  static final List<Document> productsStatic = [
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
    Document("SigWx",            "SigWx Low Level 00HR",   "https://www.aviationweather.gov/data/products/swl/00_sigwx_lo_us.gif"),
    Document("SigWx",            "SigWx Low Level 06HR",   "https://www.aviationweather.gov/data/products/swl/06_sigwx_lo_us.gif"),
    Document("SigWx",            "SigWx Low Level 12HR",   "https://www.aviationweather.gov/data/products/swl/12_sigwx_lo_us.gif"),
    Document("SigWx",            "SigWx Low Level 18HR",   "https://www.aviationweather.gov/data/products/swl/18_sigwx_lo_us.gif"),
    Document("SigWx",            "SigWx Mid Level 00HR",   "https://www.aviationweather.gov/data/products/swm/00_sigwx_mid_nat.gif"),
    Document("SigWx",            "SigWx Mid Level 06HR",   "https://www.aviationweather.gov/data/products/swm/06_sigwx_mid_nat.gif"),
    Document("SigWx",            "SigWx Mid Level 12HR",   "https://www.aviationweather.gov/data/products/swm/12_sigwx_mid_nat.gif"),
    Document("SigWx",            "SigWx Mid Level 18HR",   "https://www.aviationweather.gov/data/products/swm/18_sigwx_mid_nat.gif"),
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

  Widget _textReader(String path) {
    return FutureBuilder(
        future: File(path).readAsBytes(),
        builder: (context, snapshot) {
          return Scaffold(
              body: SingleChildScrollView(
                child:Text(
                  snapshot.data == null ? "" : String.fromCharCodes(snapshot.data!),
                ),
              )
          );
        }
    );
  }

  //if you don't want widget full screen then use center widget
  Widget smallImage(Document product) {
     Widget widget;

     if(product.type == DocumentsScreen.userDocuments) {
       widget =
           Column(children: [
               Flexible(flex: 1, child: Row(children: [
                 if(PathUtils.isTextFile(product.url))
                   TextButton(
                       child: const Text("Open"), onPressed: () {
                         Navigator.of(context).push(
                           PageRouteBuilder(
                             opaque: false,
                             pageBuilder: (BuildContext context, _, __) => Scaffold(
                               appBar: AppBar(
                                 backgroundColor: Constants.appBarBackgroundColor,
                                 title: Text(product.name),
                               ),
                               body: _textReader(product.url)
                               )
                             )
                           );
                         }
                   ),
                 if(PathUtils.isPdfFile(product.url))
                   TextButton(
                       child: const Text("Open"), onPressed: () {
                     Navigator.of(context).push(
                         PageRouteBuilder(
                             opaque: false,
                             pageBuilder: (BuildContext context, _, __) => PdfViewer(product.url)
                         )
                     );
                   }
                   ),
                 TextButton(onPressed: () {
                   final box = context.findRenderObject() as RenderBox?;
                   Share.shareXFiles(
                     [XFile(product.url)],
                     sharePositionOrigin: box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size,
                   );
                 }, child: const Text("Share")),
                 if(((products.length - productsStatic.length) > 1) && product.canBeDeleted)
                   TextButton(
                     onLongPress: () { // delete on long press
                       setState(() {
                         PathUtils.deleteFile(product.url);
                         products.remove(product);
                       });
                     },
                     onPressed: () {},
                     child: const Text("Delete")
                   ),
               ])
             ),
           ]);
     }
     else {
       // pictures
       widget = WidgetZoom(
           heroAnimationTag: product.name,
           zoomWidget: CachedNetworkImage(
             imageUrl: product.url,
             cacheManager: FileCacheManager().networkCacheManager,));
     }
    return Padding(padding: const EdgeInsets.fromLTRB(10, 0, 0, 10),
      child: Center(
          child: Column(
              children: [
                SizedBox(width: 256, height: 128, child: widget),
                Text(product.name),
              ]
          )),
    );
  }
  

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: PathUtils.getDocumentsNames(Storage().dataDir),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return _makeContent(snapshot.data);
          }
          else {
            return _makeContent(null);
          }
        }
    );
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      String? path = result.files.single.path;
      if(path != null) {
        File file = File(path);
        // copy now
        file.copy(PathUtils.getFilePath(
            Storage().dataDir, PathUtils.filename(file.path)));
      }
    }
  }

Widget _makeContent(List<String>? docs) {

    if(null == docs) {
      return Container();
    }

    String filter = Storage().settings.getDocumentPage();

    products = [];
    products.addAll(productsStatic);

    // always show user db
    Document user = Document(DocumentsScreen.userDocuments, "User's Data", PathUtils.getFilePath(Storage().dataDir, "user.db"));
    user.canBeDeleted = false;
    products.add(user);

    for(String doc in docs) {
      products.add(Document(DocumentsScreen.userDocuments, PathUtils.filename(doc), doc));
    }

    List<String> ctypes = products.map((e) => e.type).toSet().toList(); // toSet for unique.
    ctypes.insert(0, DocumentsScreen.allDocuments); // everything shows
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Documents"),
          actions: [
            TextButton(onPressed: () {
              _pickFile().then((value) => setState(() {
                products.clear(); // rebuild so the doc appears in list immediately.
              }));},
              child: const Text("Import"),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 0), child:
              DropdownButtonHideUnderline(child:
                DropdownButton2<String>( // airport selection
                  buttonStyleData: ButtonStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Constants.dropDownButtonBackgroundColor),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                  ),
                  isExpanded: false,
                  value: filter,
                  items: ctypes.map((String e) => DropdownMenuItem<String>(value: e, child: Text(e, style: TextStyle(fontSize: Constants.dropDownButtonFontSize)))).toList(),
                  onChanged: (value) {
                    setState(() {
                      Storage().settings.setDocumentPage(value ?? DocumentsScreen.allDocuments);
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
                if(p.type == filter || filter == DocumentsScreen.allDocuments)
                  smallImage(p),
            ],
          ),
      ),
    );
  }
}


class Document {
  final String name;
  final String url;
  final String type;
  bool canBeDeleted = true;
  Document(this.type, this.name, this.url);
}

