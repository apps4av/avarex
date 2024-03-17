import 'dart:io';

import 'package:avaremp/path_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';


/// Represents the Homepage for Navigation
class PdfViewer extends StatefulWidget {

  final String url;

  const PdfViewer(this.url, {super.key});

  @override
  State<StatefulWidget> createState() => PdfViewerState();
}

class PdfViewerState extends State<PdfViewer> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final GlobalKey<SearchToolbarState> _textSearchKey = GlobalKey();
  late bool _showToolbar;
  late bool _showScrollHead;

  /// Ensure the entry history of Text search.
  LocalHistoryEntry? _historyEntry;

  @override
  void initState() {
    _showToolbar = false;
    _showScrollHead = true;
    super.initState();
  }

  /// Ensure the entry history of text search.
  void _ensureHistoryEntry() {
    if (_historyEntry == null) {
      final ModalRoute<dynamic>? route = ModalRoute.of(context);
      if (route != null) {
        _historyEntry = LocalHistoryEntry(onRemove: _handleHistoryEntryRemoved);
        route.addLocalHistoryEntry(_historyEntry!);
      }
    }
  }

  /// Remove history entry for text search.
  void _handleHistoryEntryRemoved() {
    _textSearchKey.currentState?.clearSearch();
    setState(() {
      _showToolbar = false;
    });
    _historyEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _showToolbar
          ? AppBar(
        leading:  const BackButton(),

        title: SafeArea(
          child: SearchToolbar(
            key: _textSearchKey,
            showTooltip: true,
            controller: _pdfViewerController,
            onTap: (Object toolbarItem) async {
              if (toolbarItem.toString() == 'Cancel Search') {
                setState(() {
                  _showToolbar = false;
                  _showScrollHead = true;
                  if (Navigator.canPop(context)) {
                    Navigator.maybePop(context);
                  }
                });
              }
              if (toolbarItem.toString() == 'noResultFound') {
                setState(() {
                  _textSearchKey.currentState?._showToast = true;
                });
                await Future.delayed(const Duration(seconds: 1));
                setState(() {
                  _textSearchKey.currentState?._showToast = false;
                });
              }
            },
          ),
        ),
        automaticallyImplyLeading: false,
      )
          : AppBar(
        title: Text(
          PathUtils.filename(widget.url),
        ),
        leading:  const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.search,
            ),
            onPressed: () {
              setState(() {
                _showScrollHead = false;
                _showToolbar = true;
                _ensureHistoryEntry();
              });
            },
          ),
        ],
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          SfPdfViewer.file(
            File(widget.url),
            controller: _pdfViewerController,
            canShowScrollHead: _showScrollHead,
          ),
          Visibility(
            visible: _textSearchKey.currentState?._showToast ?? false,
            child: Align(
              alignment: Alignment.center,
              child: Flex(
                direction: Axis.horizontal,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    padding:
                    const EdgeInsets.only(left: 15, top: 7, right: 15, bottom: 7),
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: const BorderRadius.all(
                        Radius.circular(16.0),
                      ),
                    ),
                    child: const Text(
                      'No result',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signature for the [SearchToolbar.onTap] callback.
typedef SearchTapCallback = void Function(Object item);

/// SearchToolbar widget
class SearchToolbar extends StatefulWidget {
  ///it describe the search toolbar constructor
  const SearchToolbar({
    this.controller,
    this.onTap,
    this.showTooltip = true,
    super.key,
  });

  /// Indicates whether the tooltip for the search toolbar items need to be shown or not.
  final bool showTooltip;

  /// An object that is used to control the [SfPdfViewer].
  final PdfViewerController? controller;

  /// Called when the search toolbar item is selected.
  final SearchTapCallback? onTap;

  @override
  SearchToolbarState createState() => SearchToolbarState();
}

/// State for the SearchToolbar widget
class SearchToolbarState extends State<SearchToolbar> {
  /// Indicates whether search is initiated or not.
  bool _isSearchInitiated = false;

  /// Indicates whether search toast need to be shown or not.
  bool _showToast = false;

  ///An object that is used to retrieve the current value of the TextField.
  final TextEditingController _editingController = TextEditingController();

  /// An object that is used to retrieve the text search result.
  PdfTextSearchResult _pdfTextSearchResult = PdfTextSearchResult();

  ///An object that is used to obtain keyboard focus and to handle keyboard events.
  FocusNode? focusNode;

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode();
    focusNode?.requestFocus();
  }

  @override
  void dispose() {
    // Clean up the focus node when the Form is disposed.
    focusNode?.dispose();
    _pdfTextSearchResult.removeListener(() {});
    super.dispose();
  }

  ///Clear the text search result
  void clearSearch() {
    _isSearchInitiated = false;
    _pdfTextSearchResult.clear();
  }

  ///Display the Alert dialog to search from the beginning
  void _showSearchAlertDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.all(0),
          title: const Text('Search Result'),
          content: const SizedBox(
              width: 328.0,
              child: Text(
                  'No more occurrences found. Would you like to continue to search from the beginning?')),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                setState(() {
                  _pdfTextSearchResult.nextInstance();
                });
                Navigator.of(context).pop();
              },
              child: const Text(
                'YES',
                style: TextStyle(
                    fontStyle: FontStyle.normal,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _pdfTextSearchResult.clear();
                  _editingController.clear();
                  _isSearchInitiated = false;
                  focusNode?.requestFocus();
                });
                Navigator.of(context).pop();
              },
              child: const Text(
                'NO',
                style: TextStyle(
                    fontStyle: FontStyle.normal,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(
          child: TextFormField(
            style: const TextStyle(
                fontSize: 16),
            enableInteractiveSelection: false,
            focusNode: focusNode,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            controller: _editingController,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Find...',
            ),
            onChanged: (text) {
              if (_editingController.text.isNotEmpty) {
                setState(() {});
              }
            },
            onFieldSubmitted: (String value) {
              if (kIsWeb) {
                _pdfTextSearchResult =
                    widget.controller!.searchText(_editingController.text);
                if (_pdfTextSearchResult.totalInstanceCount == 0) {
                  widget.onTap?.call('noResultFound');
                }
                setState(() {});
              } else {
                _isSearchInitiated = true;
                _pdfTextSearchResult =
                    widget.controller!.searchText(_editingController.text);
                _pdfTextSearchResult.addListener(() {
                  if (super.mounted) {
                    setState(() {});
                  }
                  if (!_pdfTextSearchResult.hasResult &&
                      _pdfTextSearchResult.isSearchCompleted) {
                    widget.onTap?.call('noResultFound');
                  }
                });
              }
            },
          ),
        ),
        Visibility(
          visible:
          !_pdfTextSearchResult.isSearchCompleted && _isSearchInitiated,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ),
        Visibility(
          visible: _pdfTextSearchResult.hasResult,
          child: Row(
            children: [
              Text(
                '${_pdfTextSearchResult.currentInstanceIndex}',
                style: const TextStyle(
                    fontSize: 16),
              ),
              const Text(
                ' of ',
                style: TextStyle(
                    fontSize: 16),
              ),
              Text(
                '${_pdfTextSearchResult.totalInstanceCount}',
                style: const TextStyle(
                    fontSize: 16),
              ),
              Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(
                    Icons.navigate_before,
                    size: 24,
                  ),
                  onPressed: () {
                    setState(() {
                      _pdfTextSearchResult.previousInstance();
                    });
                    widget.onTap!.call('Previous Instance');
                  },
                  tooltip: widget.showTooltip ? 'Previous' : null,
                ),
              ),
              Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(
                    Icons.navigate_next,
                    size: 24,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_pdfTextSearchResult.currentInstanceIndex ==
                          _pdfTextSearchResult.totalInstanceCount &&
                          _pdfTextSearchResult.currentInstanceIndex != 0 &&
                          _pdfTextSearchResult.totalInstanceCount != 0 &&
                          _pdfTextSearchResult.isSearchCompleted) {
                        _showSearchAlertDialog(context);
                      } else {
                        widget.controller!.clearSelection();
                        _pdfTextSearchResult.nextInstance();
                      }
                    });
                    widget.onTap!.call('Next Instance');
                  },
                  tooltip: widget.showTooltip ? 'Next' : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}