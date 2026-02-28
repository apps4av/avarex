import 'package:avaremp/utils/toast.dart';
import 'package:universal_io/io.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/utils/pdf_viewer.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/kml_viewer_screen.dart';
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
  List<String> folders = [];
  String currentFolderPath = "";
  
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

  @override
  void initState() {
    super.initState();
    currentFolderPath = Storage().dataDir;
  }

  String get _currentBasePath => currentFolderPath.isEmpty ? Storage().dataDir : currentFolderPath;
  
  bool get _isInSubfolder => currentFolderPath != Storage().dataDir && currentFolderPath.isNotEmpty;

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

  Future<void> _navigateToCreateFolder() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CreateFolderScreen(basePath: _currentBasePath),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _showDeleteFolderDialog(String folderPath) async {
    String folderName = PathUtils.filename(folderPath);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Delete folder "$folderName" and all its contents?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              bool success = await PathUtils.deleteFolder(folderPath);
              if (mounted) {
                Navigator.pop(context);
                if (success) {
                  Toast.showToast(context, "Folder deleted.", const Icon(Icons.check, color: Colors.green), 3);
                  setState(() {});
                } else {
                  Toast.showToast(context, "Failed to delete folder.", const Icon(Icons.error, color: Colors.red), 3);
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToMoveFile(Document document) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => MoveFileScreen(
          document: document,
          currentFolderPath: currentFolderPath,
          isInSubfolder: _isInSubfolder,
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() {
        products.remove(document);
      });
    }
  }

  Widget _buildFolderItem(String folderPath) {
    String folderName = PathUtils.filename(folderPath);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 0, 10),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              width: 256,
              height: 128,
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          currentFolderPath = folderPath;
                          Storage().settings.setDocumentPage(DocumentsScreen.userDocuments);
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.all(10.0),
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).colorScheme.primary),
                          borderRadius: const BorderRadius.all(Radius.circular(10)),
                        ),
                        child: SizedBox(
                          width: Constants.screenWidth(context) / 5,
                          child: const Icon(Icons.folder, size: 48),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () => _showDeleteFolderDialog(folderPath),
                        tooltip: "Delete folder",
                      ),
                      if (Constants.shouldShare)
                        IconButton(
                          icon: const Icon(Icons.ios_share, size: 20),
                          onPressed: () => _exportFolder(folderPath),
                          tooltip: "Export folder contents",
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Text(folderName),
          ],
        ),
      ),
    );
  }

  Future<void> _exportFolder(String folderPath) async {
    List<String> files = await PathUtils.getDocumentsNames(folderPath);
    if (files.isEmpty) {
      if (mounted) {
        Toast.showToast(context, "Folder is empty.", const Icon(Icons.info, color: Colors.orange), 3);
      }
      return;
    }
    
    List<XFile> xFiles = files.map((f) => XFile(f)).toList();
    final params = ShareParams(
      files: xFiles,
      sharePositionOrigin: const Rect.fromLTWH(128, 128, 1, 1),
    );
    SharePlus.instance.share(params).then((value) {
      if (mounted) {
        bool success = value.status == ShareResultStatus.success;
        Toast.showToast(context, "Export ${success ? "successful" : "failed"}", Icon(Icons.info, color: success ? Colors.green : Colors.red), 3);
      }
    });
  }

  Widget _makeActions(Widget main, Document product) {
    int userDocCount = _isInSubfolder ? products.length : (products.length - productsStatic.length);
    bool canDelete = (userDocCount > 1 || _isInSubfolder) && (product.name != 'User Data');
    
    return Column(children:[
      Expanded(flex:2, child: main),
        Row(children:[
          if(canDelete)
            Padding(padding: const EdgeInsets.fromLTRB(10, 5, 5, 5), child: Dismissible(key: GlobalKey(),
                background: const Icon(Icons.delete_forever),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) {
                  setState(() {
                    PathUtils.deleteFile(product.url);
                    products.remove(product);
                  });
                },
                child: const Column(children:[
                  Icon(Icons.swipe_left, size: 18), Text("Delete", style: TextStyle(fontSize: 8))
                ])
            )),
          if(product.type == DocumentsScreen.userDocuments && product.name != 'User Data')
            IconButton(
              icon: Icon(Icons.drive_file_move_outline, size: 18),
              onPressed: () => _navigateToMoveFile(product),
              tooltip: "Move to folder",
            ),
          if(Constants.shouldShare)
            IconButton(
              icon: const Icon(Icons.share, size: 18),
              onPressed: () {
                final params = ShareParams(
                  files: [XFile(product.url)],
                  sharePositionOrigin: const Rect.fromLTWH(128, 128, 1, 1),
                );
                SharePlus.instance.share(params).then((value) {
                  if(mounted) {
                    bool success = value.status == ShareResultStatus.success;
                    Toast.showToast(context, "Sharing of file ${success ? "successful" : "failed"}", Icon(Icons.info, color: success ? Colors.green : Colors.red,), 30);
                  }
                });
              },
              tooltip: "Share",
            ),
        ])
    ]);
  }

  Icon getIcon(Document product) {
    if(PathUtils.isTextFile(product.url)) {
      return const Icon(Icons.text_snippet);
    }
    else if(PathUtils.isPdfFile(product.url) && Constants.shouldShowPdf) {
      return const Icon(Icons.picture_as_pdf);
    }
    else if(PathUtils.isJSONFile(product.url)) {
      return const Icon(Icons.map);
    }
    else {
      return const Icon(Icons.file_copy);
    }
  }

  //if you don't want widget full screen then use center widget
  Widget smallImage(Document product) {
     Widget widget;
     if(product.type == DocumentsScreen.userDocuments) {
       widget = GestureDetector(
         onTap: () {
           if(PathUtils.isTextFile(product.url)) {
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
           else if(PathUtils.isPdfFile(product.url) && Constants.shouldShowPdf) {
             Navigator.of(context).push(
                 PageRouteBuilder(
                     opaque: false,
                     pageBuilder: (BuildContext context, _, __) => PdfViewer(product.url)
                 )
             );
           }
          else if(PathUtils.isJSONFile(product.url)) {
            Toast.showToast(context, "Parsing GeoJSON file.", null, 3);
            File(product.url).readAsString().then((String value) {
              try {
                Storage().geoParser.parse(value).then((value) {
                  setState(() {
                    Toast.showToast(context, "GeoJSON file read. Shapes will appear on the map when GeoJSON layer is On.", null, 3);
                  });
                });
              }
              catch(e) {
                setState(() {
                  Toast.showToast(context, "Error reading the GeoJSON file.", null, 3);
                });
              }
            });
          }
          else if(PathUtils.isKmlFile(product.url)) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => KmlViewerScreen(kmlPath: product.url),
              ),
            );
          }
        },
         child: _makeActions(Container(
           margin: const EdgeInsets.all(10.0),
           decoration: BoxDecoration(
             border: Border.all(color: Theme.of(context).colorScheme.primary),
             borderRadius: const BorderRadius.all(Radius.circular(10)),),
           child: SizedBox(width: Constants.screenWidth(context) / 5, child: getIcon(product))), product));
     }
     else {
       // pictures
       widget = WidgetZoom(
           heroAnimationTag: product.name,
           zoomWidget: CachedNetworkImage(
             imageUrl: product.url,
             cacheManager: FileCacheManager().documentsCacheManager,));
     }

     // local picture files. deal with zoom widget
     if(PathUtils.isPictureFile(product.url) && product.type == DocumentsScreen.userDocuments) {
       // pictures
       widget = _makeActions(WidgetZoom(heroAnimationTag: product.name, zoomWidget: Image.file(File(product.url))), product);
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
        future: Future.wait([
          PathUtils.getDocumentsNames(_currentBasePath),
          PathUtils.getFolderNames(_currentBasePath),
        ]),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            List<String> docs = snapshot.data![0];
            List<String> foldersList = snapshot.data![1];
            return _makeContent(docs, foldersList);
          }
          else {
            return _makeContent(null, null);
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
        file.copy(PathUtils.getFilePath(
            _currentBasePath, PathUtils.filename(file.path)));
      }
    }
  }

  Widget _makeContent(List<String>? docs, List<String>? foldersList) {

    if(null == docs) {
      return Container();
    }

    String filter = Storage().settings.getDocumentPage();
    folders = foldersList ?? [];

    products = [];
    
    if (!_isInSubfolder) {
      products.addAll(productsStatic);
    }

    if (!_isInSubfolder) {
      Document db = Document(DocumentsScreen.userDocuments, "User Data",
          PathUtils.getFilePath(Storage().dataDir, "user.db"));
      products.add(db);
    }

    for(String doc in docs) {
      products.add(Document(DocumentsScreen.userDocuments, PathUtils.filename(doc), doc));
    }

    List<String> ctypes = products.map((e) => e.type).toSet().toList();
    ctypes.insert(0, DocumentsScreen.allDocuments);
    
    String currentFolderName = _isInSubfolder ? PathUtils.filename(currentFolderPath) : "Documents";
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        leading: _isInSubfolder 
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  currentFolderPath = Storage().dataDir;
                });
              },
            )
          : null,
        title: Text(currentFolderName),
          actions: [
            IconButton(
              icon: const Icon(Icons.create_new_folder),
              onPressed: _navigateToCreateFolder,
              tooltip: "Create folder",
            ),
            TextButton(onPressed: () {
              _pickFile().then((value) => setState(() {
                Toast.showToast(context, "Import complete.", const Icon(Icons.info, color: Colors.green), 3);
                Storage().settings.setDocumentPage(DocumentsScreen.userDocuments);
                products.clear();
              }));},
              child: Tooltip(message: "Import text (.txt), GeoJSON (.geojson), ${Constants.shouldShowPdf ? "PDF documents (.pdf), " : ""}user data (user.db)", child: const Text("Import")),
            ),
            if (!_isInSubfolder)
              Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 0), child:
                DropdownButtonHideUnderline(child:
                  DropdownButton2<String>(
                    buttonStyleData: ButtonStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
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
              for(String folder in folders)
                if(filter == DocumentsScreen.allDocuments || filter == DocumentsScreen.userDocuments)
                  _buildFolderItem(folder),
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
  Document(this.type, this.name, this.url);
}


class CreateFolderScreen extends StatefulWidget {
  final String basePath;
  
  const CreateFolderScreen({super.key, required this.basePath});
  
  @override
  State<CreateFolderScreen> createState() => _CreateFolderScreenState();
}

class _CreateFolderScreenState extends State<CreateFolderScreen> {
  final TextEditingController _controller = TextEditingController();
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  Future<void> _createFolder() async {
    if (_controller.text.trim().isNotEmpty) {
      bool success = await PathUtils.createFolder(widget.basePath, _controller.text.trim());
      if (mounted) {
        if (success) {
          Toast.showToast(context, "Folder created.", const Icon(Icons.check, color: Colors.green), 3);
          Navigator.pop(context, true);
        } else {
          Toast.showToast(context, "Failed to create folder.", const Icon(Icons.error, color: Colors.red), 3);
        }
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text('Create Folder'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Folder name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (_) => _createFolder(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _createFolder,
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}


class MoveFileScreen extends StatefulWidget {
  final Document document;
  final String currentFolderPath;
  final bool isInSubfolder;
  
  const MoveFileScreen({
    super.key,
    required this.document,
    required this.currentFolderPath,
    required this.isInSubfolder,
  });
  
  @override
  State<MoveFileScreen> createState() => _MoveFileScreenState();
}

class _MoveFileScreenState extends State<MoveFileScreen> {
  List<String> _folders = [];
  String? _selectedFolder;
  bool _loading = true;
  
  @override
  void initState() {
    super.initState();
    _loadFolders();
  }
  
  Future<void> _loadFolders() async {
    final folders = await PathUtils.getFolderNames(Storage().dataDir);
    if (mounted) {
      setState(() {
        _folders = folders.where((f) => f != widget.currentFolderPath).toList();
        _loading = false;
      });
    }
  }
  
  Future<void> _moveFile() async {
    if (_selectedFolder != null) {
      bool success;
      if (_selectedFolder == "__ROOT__") {
        success = await PathUtils.moveFileToBase(widget.document.url, Storage().dataDir);
      } else {
        success = await PathUtils.moveFileToFolder(widget.document.url, _selectedFolder!);
      }
      if (mounted) {
        if (success) {
          Toast.showToast(context, "File moved.", const Icon(Icons.check, color: Colors.green), 3);
          Navigator.pop(context, true);
        } else {
          Toast.showToast(context, "Failed to move file.", const Icon(Icons.error, color: Colors.red), 3);
        }
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: Text('Move ${widget.document.name}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Select destination:', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),
                  if (widget.isInSubfolder)
                    ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: const Text('User Documents (root)'),
                      selected: _selectedFolder == "__ROOT__",
                      onTap: () {
                        setState(() {
                          _selectedFolder = "__ROOT__";
                        });
                      },
                    ),
                  if (_folders.isEmpty && !widget.isInSubfolder)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No folders available. Create a folder first.'),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _folders.length,
                        itemBuilder: (context, index) {
                          final folder = _folders[index];
                          final folderName = PathUtils.filename(folder);
                          return ListTile(
                            leading: const Icon(Icons.folder),
                            title: Text(folderName),
                            selected: _selectedFolder == folder,
                            onTap: () {
                              setState(() {
                                _selectedFolder = folder;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _selectedFolder != null ? _moveFile : null,
                    child: const Text('Move'),
                  ),
                ],
              ),
            ),
    );
  }
}

