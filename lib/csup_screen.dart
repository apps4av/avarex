import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/airport.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/utils/pdf_viewer.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'constants.dart';

/// CSUP (Chart Supplement) for the airport the Plate tab is showing.
/// It looks and works like the Plate tab. The page list holds the airport's
/// CSUP pages. Its first item, "CSUP", shows the airport text page, the same
/// page as the first tab of a long press on the map.
class CsupScreen extends StatefulWidget {
  const CsupScreen({super.key});

  @override
  State<StatefulWidget> createState() => CsupScreenState();
}

// Regional Chart Supplement books, as file prefix and name. The download screen
// saves each one as <prefix>_CSUP.pdf next to the other chart files.
const List<(String, String)> _csupRegions = [
  ("NE", "Northeast"),
  ("NC", "North Central"),
  ("NW", "Northwest"),
  ("SE", "Southeast"),
  ("SC", "South Central"),
  ("SW", "Southwest"),
  ("EC", "East Central"),
  ("AK", "Alaska"),
  ("PAC", "Pacific"),
];

class _CsupData {
  List<String> airports = [];
  Map<String, String> pages = {}; // CSUP page name to image path
  Map<String, String> pdfs = {}; // downloaded regional PDF label to file path
  AirportDestination? airportDestination;
  String currentAirport = Storage().settings.getCurrentPlateAirport();

  Future<_CsupData> getAll() async {
    // same airport list as the Plate tab: recents, with the current one first
    airports = (await UserDatabaseHelper.db.getRecentAirports()).map((e) => e.locationID).toList();

    if (currentAirport.isEmpty) {
      if (airports.isNotEmpty) {
        currentAirport = airports[0];
      }
    }
    else {
      airports.insert(0, currentAirport);
    }
    airports = airports.toSet().toList();

    if (Constants.shouldShowPdf) {
      for (final (String prefix, String name) in _csupRegions) {
        final String path = PathUtils.getFilePath(Storage().dataDir, "${prefix}_CSUP.pdf");
        if (await File(path).exists()) {
          pdfs["$name PDF"] = path;
        }
      }
    }

    if (currentAirport.isNotEmpty) {
      pages = await PathUtils.getCsupPaths(Storage().dataDir, currentAirport);
      airportDestination = await MainDatabaseHelper.db.findAirport(currentAirport);
    }
    return this;
  }
}

class CsupScreenState extends State<CsupScreen> {

  // Value of the "CSUP" item that shows the airport text page.
  static const String textPage = "@text";
  // Prefix of the page menu items that open a regional PDF book.
  static const String pdfPrefix = "@pdf:";

  final TransformationController _transformationController = TransformationController();
  // landing and plate sync both switch the airport while this screen is up
  final Listenable _reload = Listenable.merge([
    Storage().flightStatus.flightStateChange,
    Storage().plateAirportChange,
  ]);
  late Future<_CsupData> _future;

  @override
  void initState() {
    super.initState();
    _future = _CsupData().getAll();
    _reload.addListener(_onAirportChanged);
  }

  @override
  void dispose() {
    _reload.removeListener(_onAirportChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onAirportChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _future = _CsupData().getAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CsupData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          Storage().setException('${snapshot.error}\n${snapshot.stackTrace}');
        }
        if (snapshot.hasData) {
          return _makeContent(snapshot.data!);
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }

  /// Page shown for this airport. A new airport always opens on the CSUP text
  /// page. After that, a page the pilot picked stays until the airport changes.
  String _selectedPage(_CsupData data) {
    final String airport = data.currentAirport;
    final String chosen = Storage().currentCsup;
    final bool valid = chosen == textPage || data.pages.containsKey(chosen);
    if (Storage().lastCsupAirport != airport || !valid) {
      Storage().lastCsupAirport = airport;
      Storage().currentCsup = textPage;
      _transformationController.value = Matrix4.identity();
    }
    return Storage().currentCsup;
  }

  String _pageLabel(String page) {
    if (page == textPage) {
      return "CSUP";
    }
    if (page.startsWith(pdfPrefix)) {
      return page.substring(pdfPrefix.length);
    }
    // a CSUP image that is itself named "CSUP" must not look like the text item
    return page == "CSUP" ? "CSUP (Chart)" : page;
  }

  Widget _makeContent(_CsupData data) {
    final Color overlayBg = Theme.of(context).colorScheme.surface.withAlpha(200);

    if (data.airports.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                "No CSUP available",
                style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 8),
              Text(
                "Search for an airport to view its CSUP",
                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    // keep the Plate tab on the same airport
    Storage().settings.setCurrentPlateAirport(data.currentAirport);

    final String selected = _selectedPage(data);
    // text page first, then this airport's CSUP images, then the regional PDFs last
    final List<String> pageNames = [
      textPage,
      ...data.pages.keys,
      for (final String label in data.pdfs.keys) "$pdfPrefix$label",
    ];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _makeBody(data, selected)),

          // Center button (bottom center), same spot and size as on the Plate tab
          if (selected != textPage)
            Positioned(
              bottom: Constants.bottomPaddingSize(context),
              left: 0,
              right: 0,
              child: SizedBox(
                height: Constants.bottomRowHeight,
                child: Center(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.all(5.0),
                      textStyle: const TextStyle(fontSize: Constants.bottomLabelSize),
                      minimumSize: const Size(Constants.bottomButtonWidth, Constants.bottomButtonHeight),
                      backgroundColor: overlayBg,
                      side: Constants.buttonSide(context),
                    ),
                    onPressed: () {
                      final double currentScale = _transformationController.value.getMaxScaleOnAxis();
                      _transformationController.value = Matrix4.identity()..scaleByDouble(currentScale, currentScale, 1, 1);
                    },
                    onLongPress: () {
                      _transformationController.value = Matrix4.identity();
                    },
                    child: const Text("Center"),
                  ),
                ),
              ),
            ),

          // CSUP page selector (bottom left)
          Positioned(
            bottom: Constants.bottomPaddingSize(context),
            left: Constants.bottomMenuLeft,
            child: SizedBox(
              height: Constants.bottomRowHeight,
              child: DropdownButtonHideUnderline(
                child: DropdownButton2<String>(
                  isDense: true,
                  customButton: IgnorePointer(
                    child: TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(fontSize: Constants.bottomLabelSize),
                        minimumSize: const Size(Constants.bottomButtonWidth, Constants.bottomButtonHeight),
                        backgroundColor: overlayBg,
                        side: Constants.buttonSide(context),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Opacity(opacity: 0, child: Text("Menu")),
                          Icon(Icons.menu, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                  buttonStyleData: ButtonStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                    width: Constants.screenWidth(context) * 0.8,
                    maxHeight: Constants.screenHeight(context) * 0.6,
                  ),
                  isExpanded: false,
                  valueListenable: ValueNotifier(selected),
                  items: pageNames.map((String item) {
                    final bool isSelected = item == selected;
                    final bool isPdf = item.startsWith(pdfPrefix);
                    return DropdownItem<String>(
                      value: item,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: (isPdf ? Colors.indigo : Colors.blue).withAlpha(isSelected ? 180 : 100),
                          borderRadius: BorderRadius.circular(6),
                          border: isSelected ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
                        ),
                        child: Row(
                          children: [
                            Icon(item == textPage ? Icons.info : (isPdf ? Icons.picture_as_pdf : Icons.description), size: 16, color: Colors.white),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AutoSizeText(
                                _pageLabel(item),
                                minFontSize: 8,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null && value.startsWith(pdfPrefix)) {
                      // a PDF book opens on its own screen; the page on screen stays
                      final String label = value.substring(pdfPrefix.length);
                      final String? path = data.pdfs[label];
                      if (path != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => PdfViewer(path, title: "CSUP $label")),
                        );
                      }
                      return;
                    }
                    setState(() {
                      Storage().currentCsup = value ?? textPage;
                      _transformationController.value = Matrix4.identity();
                    });
                  },
                ),
              ),
            ),
          ),

          // Airport selector (bottom right), same spot as on the Plate tab
          Positioned(
            bottom: Constants.bottomPaddingSize(context),
            right: Constants.bottomRightInset + Constants.bottomIconPadding,
            child: SizedBox(
              height: Constants.bottomRowHeight,
              child: Container(
                decoration: Constants.buttonDecoration(context, overlayBg, radius: 8),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton2<String>(
                    buttonStyleData: ButtonStyleData(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.transparent),
                    ),
                    dropdownStyleData: DropdownStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                    ),
                    isExpanded: false,
                    valueListenable: ValueNotifier(data.airports.contains(data.currentAirport) ? data.currentAirport : data.airports[0]),
                    items: data.airports.map((String item) {
                      final bool isSelected = item == data.currentAirport;
                      return DropdownItem<String>(
                        value: item,
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: Constants.dropDownButtonFontSize,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      // The Plate tab follows this airport. It also drops any
                      // procedure profile left over from the old airport.
                      Storage().settings.setCurrentPlateAirport(value ?? data.airports[0]);
                      Storage().settings.setPlateProfileVisible(false);
                      Storage().settings.setPlateProfile("");
                      _onAirportChanged();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _makeBody(_CsupData data, String selected) {
    if (selected == textPage) {
      return _makeTextPage(data);
    }
    final String? path = data.pages[selected];
    final bool invert = Storage().settings.isInvertColors();
    Widget image = path == null
        ? const SizedBox.shrink()
        : Image.file(
            File(path),
            key: ValueKey(path),
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => Center(
              child: Text(
                "Unable to load $selected",
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          );
    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.1,
      maxScale: 8,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      child: SizedBox(
        height: Constants.screenHeight(context),
        width: Constants.screenWidth(context),
        child: Constants.invertIfNeeded(image, invert),
      ),
    );
  }

  /// Same content as the Main tab of the long press screen on the map.
  Widget _makeTextPage(_CsupData data) {
    final AirportDestination? airport = data.airportDestination;
    if (airport == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            Text("No data available", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
    }
    // leave room for the bottom buttons
    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        Constants.bottomPaddingSize(context) + Constants.bottomRowHeight + 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Airport.parse(airport)),
        ],
      ),
    );
  }
}
