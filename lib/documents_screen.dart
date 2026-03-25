import 'package:avaremp/data/user_database_helper.dart';
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

/// [ShareResultStatus.unavailable] is returned on Windows (and anywhere the OS
/// does not report an outcome). Only [ShareResultStatus.dismissed] means failure.
bool _shareSheetNotCancelled(ShareResult result) =>
    result.status != ShareResultStatus.dismissed;

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
      padding: const EdgeInsets.all(8),
      child: Card(
        elevation: 2,
        color: Colors.amber.withAlpha(40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              currentFolderPath = folderPath;
              Storage().settings.setDocumentPage(DocumentsScreen.userDocuments);
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.folder_rounded,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  folderName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Dismissible(
                        key: GlobalKey(),
                        background: const Icon(Icons.delete_forever),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (direction) async {
                          List<String> files = await PathUtils.getDocumentsNames(folderPath);
                          List<String> subfolders = await PathUtils.getFolderNames(folderPath);
                          if (files.isNotEmpty || subfolders.isNotEmpty) {
                            if (mounted) {
                              Toast.showToast(context, "Cannot delete non-empty folder.", const Icon(Icons.warning, color: Colors.orange), 3);
                            }
                            return false;
                          }
                          return true;
                        },
                        onDismissed: (direction) async {
                          await PathUtils.deleteFolder(folderPath);
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        child: const Column(
                          children: [
                            Icon(Icons.swipe_left, size: 18),
                            Text("Delete", style: TextStyle(fontSize: 8)),
                          ],
                        ),
                      ),
                    ),
                    if (Constants.shouldShare)
                      IconButton(
                        icon: const Icon(Icons.ios_share, size: 20),
                        onPressed: () => _exportFolder(folderPath),
                        tooltip: "Export folder contents",
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
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
      title: PathUtils.filename(folderPath),
      sharePositionOrigin: const Rect.fromLTWH(128, 128, 1, 1),
    );
    SharePlus.instance.share(params).then((value) {
      if (mounted) {
        final ok = _shareSheetNotCancelled(value);
        Toast.showToast(context, "Export ${ok ? "successful" : "failed"}", Icon(Icons.info, color: ok ? Colors.green : Colors.red), 3);
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
                  title: product.name,
                  sharePositionOrigin: const Rect.fromLTWH(128, 128, 1, 1),
                );
                SharePlus.instance.share(params).then((value) {
                  if(mounted) {
                    final ok = _shareSheetNotCancelled(value);
                    Toast.showToast(context, "Sharing of file ${ok ? "successful" : "failed"}", Icon(Icons.info, color: ok ? Colors.green : Colors.red,), 30);
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
    else if(PathUtils.isKmlFile(product.url)) {
      return const Icon(Icons.route);
    }
    else {
      return const Icon(Icons.file_copy);
    }
  }

  IconData _getFilterIcon(String filter) {
    switch (filter) {
      case DocumentsScreen.allDocuments:
        return Icons.grid_view;
      case DocumentsScreen.userDocuments:
        return Icons.folder;
      case "WPC":
        return Icons.cloud;
      case "SigWx":
        return Icons.warning_amber;
      case "Misc.":
        return Icons.more_horiz;
      case "Winds/Temp":
        return Icons.air;
      default:
        if (filter.contains("AIRMET")) {
          return Icons.ac_unit;
        } else if (filter.contains("Forecast")) {
          return Icons.wb_sunny;
        }
        return Icons.description;
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
           decoration: BoxDecoration(
             color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
             borderRadius: BorderRadius.circular(8),
           ),
           child: Center(
             child: Icon(
               getIcon(product).icon,
               size: 36,
               color: Theme.of(context).colorScheme.primary,
             ),
           ),
         ), product));
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

     return Padding(
       padding: const EdgeInsets.all(8),
       child: Card(
         elevation: 1,
        color: Theme.of(context).colorScheme.primaryContainer.withAlpha(40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
           padding: const EdgeInsets.all(8),
           child: Column(
             children: [
               Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: widget)),
               const SizedBox(height: 6),
               Text(
                 product.name,
                 style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                 maxLines: 2,
                 overflow: TextOverflow.ellipsis,
                 textAlign: TextAlign.center,
               ),
             ],
           ),
         ),
       ),
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

  /// Returns true if a file was copied into [_currentBasePath]. The source
  /// [File.copy] future must be awaited; otherwise the UI refresh can run before
  /// the write finishes (often seen on Windows).
  Future<bool> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        return false;
      }

      final picked = result.files.single;
      final String destPath =
          PathUtils.getFilePath(_currentBasePath, picked.name);

      final srcPath = picked.path;
      final sameAsDest = srcPath != null &&
          srcPath.isNotEmpty &&
          PathUtils.sameFilePath(srcPath, destPath);
      if (sameAsDest) {
        return true;
      }

      final replacesUserDb =
          PathUtils.filename(destPath).toLowerCase() == 'user.db';
      if (replacesUserDb) {
        await UserDatabaseHelper.invalidateConnection();
        final existing = File(destPath);
        if (await existing.exists()) {
          await existing.delete();
        }
      }

      if (picked.path != null && picked.path!.isNotEmpty) {
        await File(picked.path!).copy(destPath);
      } else if (picked.bytes != null) {
        await File(destPath).writeAsBytes(picked.bytes!, flush: true);
      } else {
        if (mounted) {
          Toast.showToast(
            context,
            "Could not access file contents.",
            const Icon(Icons.warning, color: Colors.orange),
            3,
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      if (mounted) {
        Toast.showToast(
          context,
          "Import failed: $e",
          const Icon(Icons.error, color: Colors.red),
          5,
        );
      }
      return false;
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
              tooltip: "Back to Documents",
            )
          : null,
        title: Text(currentFolderName),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _navigateToCreateFolder,
            tooltip: "Create folder",
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () async {
              final ok = await _pickFile();
              if (!mounted || !ok) return;
              setState(() {
                Toast.showToast(context, "Import complete.", const Icon(Icons.info, color: Colors.green), 3);
                Storage().settings.setDocumentPage(DocumentsScreen.userDocuments);
                products.clear();
              });
            },
            tooltip: "Import text (.txt), GeoJSON (.geojson), KML (.kml), ${Constants.shouldShowPdf ? "PDF documents (.pdf), " : ""}user data (user.db)",
          ),
          if (!_isInSubfolder)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton2<String>(
                  buttonStyleData: ButtonStyleData(
                    height: 36,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                  ),
                  isExpanded: false,
                  value: filter,
                  items: ctypes.map((String e) => DropdownMenuItem<String>(
                    value: e,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getFilterIcon(e), size: 16),
                        const SizedBox(width: 8),
                        Text(e, style: TextStyle(fontSize: Constants.dropDownButtonFontSize)),
                      ],
                    ),
                  )).toList(),
                  onChanged: (value) {
                    setState(() {
                      Storage().settings.setDocumentPage(value ?? DocumentsScreen.allDocuments);
                    });
                  },
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(filter),
    );
  }

  Widget _buildBody(String filter) {
    final filteredFolders = (filter == DocumentsScreen.allDocuments || filter == DocumentsScreen.userDocuments) ? folders : <String>[];
    final filteredProducts = products.where((p) => p.type == filter || filter == DocumentsScreen.allDocuments).toList();

    if (filteredFolders.isEmpty && filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              _isInSubfolder ? "This folder is empty" : "No documents found",
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Use Import to add files",
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.9,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: filteredFolders.length + filteredProducts.length,
      itemBuilder: (context, index) {
        if (index < filteredFolders.length) {
          return _buildFolderItem(filteredFolders[index]);
        } else {
          return smallImage(filteredProducts[index - filteredFolders.length]);
        }
      },
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.create_new_folder, size: 20),
            SizedBox(width: 8),
            Text('Create Folder'),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "New Folder",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        labelText: 'Folder name',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.folder_outlined),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                      ),
                      autofocus: true,
                      onSubmitted: (_) => _createFolder(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _createFolder,
              icon: const Icon(Icons.add),
              label: const Text('Create Folder'),
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.drive_file_move, size: 20),
            SizedBox(width: 8),
            Text('Move File'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.description, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.document.name,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select destination:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.isInSubfolder)
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.folder_open, color: Theme.of(context).colorScheme.primary),
                        title: const Text('User Documents (root)'),
                        selected: _selectedFolder == "__ROOT__",
                        selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        trailing: _selectedFolder == "__ROOT__" ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
                        onTap: () {
                          setState(() {
                            _selectedFolder = "__ROOT__";
                          });
                        },
                      ),
                    ),
                  if (_folders.isEmpty && !widget.isInSubfolder)
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Icon(Icons.folder_off, size: 48, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            'No folders available',
                            style: TextStyle(color: Theme.of(context).colorScheme.outline),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Create a folder first',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                          ),
                        ],
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _folders.length,
                        itemBuilder: (context, index) {
                          final folder = _folders[index];
                          final folderName = PathUtils.filename(folder);
                          final isSelected = _selectedFolder == folder;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              leading: Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
                              title: Text(folderName),
                              selected: isSelected,
                              selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
                              onTap: () {
                                setState(() {
                                  _selectedFolder = folder;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _selectedFolder != null ? _moveFile : null,
                    icon: const Icon(Icons.drive_file_move),
                    label: const Text('Move Here'),
                  ),
                ],
              ),
            ),
    );
  }
}

