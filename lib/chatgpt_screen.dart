import 'dart:convert';

import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:avaremp/data/user_database_helper.dart';
import 'package:sqflite/sqflite.dart';

import 'logbook/totals.dart';

class ChatGptScreen extends StatefulWidget {
  const ChatGptScreen({super.key});

  @override
  State<ChatGptScreen> createState() => _ChatGptScreenState();
}

class _ChatMessage {
  final String role; // "user" | "assistant"
  final String content;

  _ChatMessage({required this.role, required this.content});
}

class _ChatSessionState {
  final List<_ChatMessage> messages = [];

  void addUserMessage(String text) {
    messages.add(_ChatMessage(role: "user", content: text));
  }

  void addAssistantMessage(String text) {
    messages.add(_ChatMessage(role: "assistant", content: text));
  }
}


class _ChatGptScreenState extends State<ChatGptScreen> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final _ChatSessionState _session = _ChatSessionState();
  bool _isSending = false;
  String _selectedCategory = 'Logbook';
  final List<String> _categories = [
    'Logbook',
    'Flight plan',
  ];
  String? _categoryContext; // last loaded summary for selected category
  String? _categoryError;
  // Example queries per category
  final Map<String, List<String>> _exampleQueries = {
    'Logbook': [
      'Summarize my recent flight time by category.',
      'How many night landings in the last 90 days?',
      'What’s my total PIC time this year?',
    ],
    'Flight plan': [
      'Suggest fuel stops for my current route.',
      'Estimate flight time with current winds.',
      'Identify potential alternates along the route.',
    ],
    'Aircraft': [
      'Which aircraft do I fly most often?',
      'Summarize key performance numbers for my aircraft.',
      'What’s my recent time in this aircraft?',
    ],
  };
  String? _selectedExample;
  bool _isUploading = false;
  bool _isAssistantReady = false;

  @override
  void initState() {
    super.initState();
    _discoverExtraCategories();
    _loadCategoryContext();
    _isAssistantReady = Storage().settings.getOpenAiAssistantId().isNotEmpty &&
        Storage().settings.getOpenAiVectorStoreId().isNotEmpty;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String originalText = _inputController.text.trim();
    if (originalText.isEmpty || _isSending) return;

    final String apiKey = Storage().settings.getOpenAiApiKey();
    if (apiKey.isEmpty) {
      if (!mounted) return;
      MapScreenState.showToast(context, "Set API key first", Icon(Icons.error, color: Colors.red,), 3);
      return;
    }

    String finalText = originalText;
    try {
      finalText = await _augmentQueryIfNeeded(originalText);
    } catch (_) {
      // Ignore augmentation errors and proceed with original text
    }

    // Append selected category context before sending
    final String finalWithCategory = await _augmentWithSelectedCategory(finalText);

    setState(() {
      _isSending = true;
      _session.addUserMessage(finalWithCategory);
      _inputController.clear();
    });

    await _scrollToBottom();

    try {
      final String fileId = Storage().settings.getOpenAiUserDbFileId();
      if (fileId.isNotEmpty) {
        // Prefer Assistants Threads/Runs if assistant has been configured
        final String assistantId = Storage().settings.getOpenAiAssistantId();
        if (assistantId.isNotEmpty) {
          try {
            String threadId = Storage().settings.getOpenAiThreadId();
            if (threadId.isEmpty) {
              final tResp = await http.post(
                Uri.parse('https://api.openai.com/v1/threads'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $apiKey',
                },
                body: jsonEncode({}),
              );
              if (tResp.statusCode >= 200 && tResp.statusCode < 300) {
                final tb = jsonDecode(tResp.body) as Map<String, dynamic>;
                threadId = tb['id']?.toString() ?? '';
                if (threadId.isNotEmpty) {
                  Storage().settings.setOpenAiThreadId(threadId);
                }
              }
            }
            if (threadId.isNotEmpty) {
              // Add only the latest user query (already augmented with category)
              await http.post(
                Uri.parse('https://api.openai.com/v1/threads/$threadId/messages'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $apiKey',
                },
                body: jsonEncode({
                  'role': 'user',
                  'content': finalWithCategory,
                }),
              );

              final runResp = await http.post(
                Uri.parse('https://api.openai.com/v1/threads/$threadId/runs'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $apiKey',
                },
                body: jsonEncode({'assistant_id': assistantId}),
              );
              if (runResp.statusCode >= 200 && runResp.statusCode < 300) {
                final runBody = jsonDecode(runResp.body) as Map<String, dynamic>;
                final String runId = runBody['id']?.toString() ?? '';
                // Poll for completion up to ~15 seconds
                for (int i = 0; i < 30; i++) {
                  await Future.delayed(const Duration(milliseconds: 500));
                  final st = await http.get(
                    Uri.parse('https://api.openai.com/v1/threads/$threadId/runs/$runId'),
                    headers: {'Authorization': 'Bearer $apiKey'},
                  );
                  if (st.statusCode >= 200 && st.statusCode < 300) {
                    final sb = jsonDecode(st.body) as Map<String, dynamic>;
                    final String status = sb['status']?.toString() ?? '';
                    if (status == 'completed' || status == 'failed' || status == 'cancelled' || status == 'expired') {
                      break;
                    }
                  }
                }
                // Fetch latest assistant message
                final msgsResp = await http.get(
                  Uri.parse('https://api.openai.com/v1/threads/$threadId/messages?limit=10'),
                  headers: {'Authorization': 'Bearer $apiKey'},
                );
                if (msgsResp.statusCode >= 200 && msgsResp.statusCode < 300) {
                  final mb = jsonDecode(msgsResp.body) as Map<String, dynamic>;
                  final List data = (mb['data'] as List?) ?? [];
                  String reply = '';
                  for (final m in data) {
                    if (m is Map && m['role'] == 'assistant') {
                      final content = m['content'];
                      if (content is List) {
                        for (final c in content) {
                          if (c is Map && c['type'] == 'text') {
                            final v = (c['text']?['value'])?.toString();
                            if (v != null && v.isNotEmpty) {
                              reply = v;
                              break;
                            }
                          }
                        }
                      }
                      if (reply.isNotEmpty) break;
                    }
                  }
                  if (reply.isNotEmpty) {
                    setState(() {
                      _session.addAssistantMessage(reply);
                    });
                    return; // handled via assistants
                  }
                }
              }
            }
          } catch (e) {
            setState(() {
              _session.addAssistantMessage('Assistant call failed: $e');
            });
          }
        }
      }

      // Fallback to chat completions
      {
        final String model = "gpt-5";
        final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
        // Try Assistants Threads/Runs if assistant has been configured
        final String assistantId = Storage().settings.getOpenAiAssistantId();
        if (assistantId.isNotEmpty) {
          try {
            String threadId = Storage().settings.getOpenAiThreadId();
            if (threadId.isEmpty) {
              final tResp = await http.post(
                Uri.parse('https://api.openai.com/v1/threads'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $apiKey',
                },
                body: jsonEncode({}),
              );
              if (tResp.statusCode >= 200 && tResp.statusCode < 300) {
                final tb = jsonDecode(tResp.body) as Map<String, dynamic>;
                threadId = tb['id']?.toString() ?? '';
                if (threadId.isNotEmpty) {
                  Storage().settings.setOpenAiThreadId(threadId);
                }
              }
            }
            if (threadId.isNotEmpty) {
              // Add only the latest user query (already augmented with category)
              await http.post(
                Uri.parse('https://api.openai.com/v1/threads/$threadId/messages'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $apiKey',
                },
                body: jsonEncode({
                  'role': 'user',
                  'content': finalWithCategory,
                }),
              );

              final runResp = await http.post(
                Uri.parse('https://api.openai.com/v1/threads/$threadId/runs'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $apiKey',
                },
                body: jsonEncode({'assistant_id': assistantId}),
              );
              if (runResp.statusCode >= 200 && runResp.statusCode < 300) {
                final runBody = jsonDecode(runResp.body) as Map<String, dynamic>;
                final String runId = runBody['id']?.toString() ?? '';
                // Poll for completion up to ~15 seconds
                for (int i = 0; i < 30; i++) {
                  await Future.delayed(const Duration(milliseconds: 500));
                  final st = await http.get(
                    Uri.parse('https://api.openai.com/v1/threads/$threadId/runs/$runId'),
                    headers: {'Authorization': 'Bearer $apiKey'},
                  );
                  if (st.statusCode >= 200 && st.statusCode < 300) {
                    final sb = jsonDecode(st.body) as Map<String, dynamic>;
                    final String status = sb['status']?.toString() ?? '';
                    if (status == 'completed' || status == 'failed' || status == 'cancelled' || status == 'expired') {
                      break;
                    }
                  }
                }
                // Fetch latest assistant message
                final msgsResp = await http.get(
                  Uri.parse('https://api.openai.com/v1/threads/$threadId/messages?limit=10'),
                  headers: {'Authorization': 'Bearer $apiKey'},
                );
                if (msgsResp.statusCode >= 200 && msgsResp.statusCode < 300) {
                  final mb = jsonDecode(msgsResp.body) as Map<String, dynamic>;
                  final List data = (mb['data'] as List?) ?? [];
                  String reply = '';
                  for (final m in data) {
                    if (m is Map && m['role'] == 'assistant') {
                      final content = m['content'];
                      if (content is List) {
                        for (final c in content) {
                          if (c is Map && c['type'] == 'text') {
                            final v = (c['text']?['value'])?.toString();
                            if (v != null && v.isNotEmpty) {
                              reply = v;
                              break;
                            }
                          }
                        }
                      }
                      if (reply.isNotEmpty) break;
                    }
                  }
                  if (reply.isNotEmpty) {
                    usedResponsesApi = true; // handled
                    setState(() {
                      _session.addAssistantMessage(reply);
                    });
                  }
                }
              }
            }
          } catch (e) {
            setState(() {
              _session.addAssistantMessage('Assistant call failed: $e');
            });
          }
        }

        final String model = "gpt-5";
        final uri = Uri.parse('https://api.openai.com/v1/chat/completions');

        final bool isGpt5 = model.toLowerCase().replaceAll('-', '') == 'gpt5' || model.toLowerCase().startsWith('gpt-5');

        final Map<String, dynamic> payload = {
          'model': model,
          'messages': _session.messages
              .map((m) => {
                    'role': m.role,
                    'content': m.content,
                  })
              .toList(),
        };

        if (isGpt5) {
          payload['max_completion_tokens'] = 10000;
          // temperature not supported for gpt-5; use default server-side
        } else {
          payload['max_tokens'] = 600;
          payload['temperature'] = 0.2;
        }

        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> body = jsonDecode(response.body);
          final String reply = body['choices']?[0]?['message']?['content']?.toString() ?? 'No response';
          setState(() {
            _session.addAssistantMessage(reply);
          });
        } else {
          setState(() {
            _session.addAssistantMessage('Error ${response.statusCode}: ${response.body}');
          });
        }
      }
    } catch (e) {
      setState(() {
        _session.addAssistantMessage('Error: $e');
      });
    } finally {
      setState(() {
        _isSending = false;
      });
      await _scrollToBottom();
    }
  }

  Future<String?> _exportUserDbToJsonFile() async {
    try {
      final Database? db = await UserDatabaseHelper.db.database;
      if (db == null) return null;
      // fetch all non-internal tables
      final List<Map<String, Object?>> tableRows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      final Map<String, dynamic> export = {};
      for (final row in tableRows) {
        final String tableName = (row['name'] ?? '').toString();
        if (tableName.isEmpty) continue;
        try {
          final rows = await db.query(tableName);
          export[tableName] = rows;
        } catch (_) {
          // ignore tables that cannot be exported
        }
      }
      final String exportPath = p.join(Storage().dataDir, 'user_export.json');
      final file = File(exportPath);
      await file.writeAsString(jsonEncode(export));
      return exportPath;
    } catch (_) {
      return null;
    }
  }

  Future<void> _uploadUserDb() async {
    if (_isUploading) return;
    final String apiKey = Storage().settings.getOpenAiApiKey();
    if (apiKey.isEmpty) {
      MapScreenState.showToast(context, "Set API key first", Icon(Icons.error, color: Colors.red,), 3);
      return;
    }
    // Export DB to JSON to meet Files API expectations
    final String? exportPath = await _exportUserDbToJsonFile();
    if (exportPath == null) {
      MapScreenState.showToast(context, "Failed to export database", Icon(Icons.error, color: Colors.red,), 3);
      return;
    }

    setState(() { _isUploading = true; });
    try {
      final uri = Uri.parse('https://api.openai.com/v1/files');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields['purpose'] = 'assistants'
        ..files.add(await http.MultipartFile.fromPath('file', exportPath, filename: 'user_export.json', contentType: MediaType('application', 'json')));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final String fileId = body['id']?.toString() ?? '';
        if (fileId.isNotEmpty) {
          Storage().settings.setOpenAiUserDbFileId(fileId);
          // Create or update vector store and assistant to reference this file
          await _ensureAssistantWithVectorStore(apiKey, fileId);
          MapScreenState.showToast(context, "Data uploaded and indexed", Icon(Icons.check_circle, color: Colors.green,), 3);
        } else {
          MapScreenState.showToast(context, "Upload ok but no file id", Icon(Icons.warning, color: Colors.orange,), 3);
        }
      } else {
        String detail;
        try {
          final Map<String, dynamic> body = jsonDecode(response.body);
          detail = body['error']?['message']?.toString() ?? response.body;
        } catch (_) {
          detail = response.body;
        }
        MapScreenState.showToast(context, "Upload failed ${response.statusCode}: ${detail.length > 160 ? detail.substring(0, 160) + '…' : detail}", Icon(Icons.error, color: Colors.red,), 5);
      }
    } catch (e) {
      MapScreenState.showToast(context, "Upload error: $e", Icon(Icons.error, color: Colors.red,), 4);
    } finally {
      if (mounted) setState(() { _isUploading = false; });
    }
  }

  Future<void> _ensureAssistantWithVectorStore(String apiKey, String fileId) async {
    try {
      String vectorStoreId = Storage().settings.getOpenAiVectorStoreId();
      String assistantId = Storage().settings.getOpenAiAssistantId();

      if (vectorStoreId.isEmpty) {
        // Create vector store and attach file
        final vsResp = await http.post(
          Uri.parse('https://api.openai.com/v1/vector_stores'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({'name': 'Avare User Data'}),
        );
        if (vsResp.statusCode >= 200 && vsResp.statusCode < 300) {
          final vsBody = jsonDecode(vsResp.body) as Map<String, dynamic>;
          vectorStoreId = vsBody['id']?.toString() ?? '';
          if (vectorStoreId.isNotEmpty) {
            Storage().settings.setOpenAiVectorStoreId(vectorStoreId);
          }
        }
      }

      if (vectorStoreId.isNotEmpty) {
        // Add file to vector store
        final attachResp = await http.post(
          Uri.parse('https://api.openai.com/v1/vector_stores/$vectorStoreId/files'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({'file_id': fileId}),
        );
        // ignore non-2xx; vector store may already contain the file
      }

      if (assistantId.isEmpty) {
        // Create assistant with file_search tool and vector store resource
        final asstResp = await http.post(
          Uri.parse('https://api.openai.com/v1/assistants'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': 'gpt-4.1-mini',
            'name': 'Avare Flight Assistant',
            'instructions': 'You are an aviation copilot for Avare. Use the provided files to answer.',
            'tools': [
              {'type': 'file_search'}
            ],
            'tool_resources': {
              'file_search': {
                'vector_store_ids': vectorStoreId.isNotEmpty ? [vectorStoreId] : []
              }
            }
          }),
        );
        if (asstResp.statusCode >= 200 && asstResp.statusCode < 300) {
          final asstBody = jsonDecode(asstResp.body) as Map<String, dynamic>;
          assistantId = asstBody['id']?.toString() ?? '';
          if (assistantId.isNotEmpty) {
            Storage().settings.setOpenAiAssistantId(assistantId);
          }
        }
      }
      if (assistantId.isNotEmpty) {
        setState(() { _isAssistantReady = true; });
      }
    } catch (_) {
      // silently ignore; user can still use normal chat
    }
  }

  Future<void> _scrollToBottom() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _discoverExtraCategories() async {
    try {
      // Aircraft available? If yes, expose as a category users commonly ask about
      final aircraft = await UserDatabaseHelper.db.getAllAircraft();
      if (aircraft.isNotEmpty && !_categories.contains('Aircraft')) {
        setState(() {
          _categories.add('Aircraft');
        });
      }
      // Plans exist? Already covered by 'Flight plan'
      // Recents/Other are not primary AI-query categories; skip unless requested
    } catch (_) {
      // ignore discovery failures
    }
  }

  String _fmtH(double h) => h.toStringAsFixed(1);

  String _formatTotalsSummary(Totals t) {
    return "total hours ${_fmtH(t.totalFlightTime)}, pilot in command ${_fmtH(t.pilotInCommand)}, dual instruction received ${_fmtH(t.dualReceived)}, solo ${_fmtH(t.soloTime)}, cross country ${_fmtH(t.crossCountryTime)}, night ${_fmtH(t.nightTime)}, actual instrument ${_fmtH(t.actualInstruments)}, simulated instrument ${_fmtH(t.simulatedInstruments)}, day landings ${t.dayLandings}, night landings ${t.nightLandings}, instrument approaches ${t.instrumentApproaches}";
  }

  Future<String> _augmentQueryIfNeeded(String text) async {
    return text;
  }

  Future<String> _augmentWithSelectedCategory(String text) async {
    await _loadCategoryContext();
    final ctx = _categoryContext?.trim();
    if (ctx == null || ctx.isEmpty) return text;
    final label = _selectedCategory;
    if (text.toLowerCase().contains('context:')) return text; // basic guard to avoid duplication
    return "$text\nContext [$label]: $ctx";
  }

  Widget _buildAviationHelpers() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategorySelector(),
          if (_categoryError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Failed to load category: \'$_categoryError\'', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
          if (_categoryContext != null && _categoryContext!.isNotEmpty) _buildCategorySummaryCard(_selectedCategory, _categoryContext!),
        ],
      ),
    );
  }

  Widget _buildCategorySelector() {
    final List<String> examples = _exampleQueries[_selectedCategory] ?? const [];
    return Row(
      children: [
        const Text('Category:'),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _selectedCategory,
          items: _categories
              .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
              .toList(),
          onChanged: (val) async {
            if (val == null) return;
            setState(() {
              _selectedCategory = val;
              _selectedExample = null; // reset example when category changes
            });
            await _loadCategoryContext();
          },
        ),
        const SizedBox(width: 16),
        if (examples.isNotEmpty) ...[
          const Text('Example:'),
          const SizedBox(width: 8),
          Flexible(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedExample,
              hint: const Text('Choose example'),
              items: examples
                  .map((q) => DropdownMenuItem<String>(
                        value: q,
                        child: Text(q, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _selectedExample = val;
                });
                _inputController.text = val;
                _inputController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _inputController.text.length),
                );
                _inputFocusNode.requestFocus();
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategorySummaryCard(String label, String summary) {
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 6, 0, 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label context', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(summary, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Future<void> _loadCategoryContext() async {
    setState(() {
      _categoryError = null;
    });
    try {
      String ctx;
      switch (_selectedCategory) {
        case 'Logbook':
          ctx = await _summarizeLogbook();
          break;
        case 'Flight plan':
          ctx = await _summarizeFlightPlan();
          break;
        default:
          ctx = '';
      }
      if (!mounted) return;
      setState(() {
        _categoryContext = ctx;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoryError = e.toString();
        _categoryContext = null;
      });
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<String> _summarizeLogbook() async {
    Totals t = await Totals.getTotals();
    return (!t.hasData) ? '' : _formatTotalsSummary(t);
  }

  Future<String> _summarizeFlightPlan() async {
    final route = Storage().route;
    final all = route.getAllDestinations();
    final names = all.map((d) => Destination.isAirway(d.type) ? d.secondaryName : d.locationID).toList();
    if (names.isEmpty) return '';

    String? windString = '';
    String? station = WindsCache.locateNearestStation(all.first.coordinate);
    if(station != null) {
      Weather? winds = Storage().winds.get("${station}06H"); // 6HR wind
      if(winds != null) {
        WindsAloft wa = winds as WindsAloft;
        windString = wa.toListRaw().join(",");
      }
    }

    String partRoute = names.isEmpty ? '' : 'route ${names.join(' ')}';
    String planWinds = windString.isEmpty ? '' : 'winds $windString';
    return [partRoute, planWinds].where((s) => s.isNotEmpty).join('; ');
  }


  Future<void> _setApiKeyDialog() async {
    final TextEditingController controller = TextEditingController(text: Storage().settings.getOpenAiApiKey());
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('API Key'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'sk-... (kept locally)'
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'API key cannot be empty';
                }
                return null;
              },
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Storage().settings.setOpenAiApiKey(controller.text.trim());
                  Navigator.of(context).pop();
                  MapScreenState.showToast(context, "API key saved", Icon(Icons.info, color: Colors.blue,), 3);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlightAI'),
        actions: [
          IconButton(
            tooltip: 'Set API key',
            onPressed: _setApiKeyDialog,
            icon: const Icon(Icons.vpn_key),
          ),
          IconButton(
            tooltip: 'Upload user.db to ChatGPT',
            onPressed: _isUploading ? null : _uploadUserDb,
            icon: _isUploading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _session.messages.length,
              itemBuilder: (context, index) {
                final m = _session.messages[index];
                final bool isUser = m.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: isUser
                        ? () {
                            _inputController.text = m.content;
                            _inputController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _inputController.text.length),
                            );
                            _inputFocusNode.requestFocus();
                          }
                        : null,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser ? Theme.of(context).colorScheme.primary : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        m.content,
                        style: TextStyle(
                          color: isUser ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildAviationHelpers(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: _inputFocusNode,
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                    label: const Text('Ask'),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
