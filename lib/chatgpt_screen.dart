import 'dart:convert';

import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:avaremp/data/user_database_helper.dart';

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

  @override
  void initState() {
    super.initState();
    _discoverExtraCategories();
    _loadCategoryContext();
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
            });
            await _loadCategoryContext();
          },
        ),
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
