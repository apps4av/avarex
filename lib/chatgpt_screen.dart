import 'dart:convert';

import 'package:avaremp/map_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/logbook/entry.dart';
import 'package:avaremp/checklist.dart';
import 'package:avaremp/wnb.dart';
import 'package:avaremp/weather/metar.dart';

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

class _LogbookTotals {
  double totalFlightTime = 0.0;
  double pilotInCommand = 0.0;
  double dualReceived = 0.0;
  double soloTime = 0.0;
  double crossCountryTime = 0.0;
  double dayTime = 0.0;
  double nightTime = 0.0;
  double actualInstruments = 0.0;
  double simulatedInstruments = 0.0;
  int dayLandings = 0;
  int nightLandings = 0;
  int instrumentApproaches = 0;
  double groundTime = 0.0;
  double flightSimulator = 0.0;

  bool get hasData {
    return totalFlightTime > 0.0 ||
        pilotInCommand > 0.0 ||
        dualReceived > 0.0 ||
        soloTime > 0.0 ||
        crossCountryTime > 0.0 ||
        dayTime > 0.0 ||
        nightTime > 0.0 ||
        actualInstruments > 0.0 ||
        simulatedInstruments > 0.0 ||
        dayLandings > 0 ||
        nightLandings > 0 ||
        instrumentApproaches > 0;
  }
}

class _ChatGptScreenState extends State<ChatGptScreen> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final _ChatSessionState _session = _ChatSessionState();
  bool _isSending = false;
  _LogbookTotals? _logbookTotals;
  bool _loadingTotals = false;
  String? _totalsError;
  String _selectedCategory = 'Logbook';
  List<String> _categories = [
    'Logbook',
    'Flight plan',
    'Weather',
    'Checklists',
    'Weight & balance',
  ];
  String? _categoryContext; // last loaded summary for selected category
  bool _loadingCategory = false;
  String? _categoryError;

  @override
  void initState() {
    super.initState();
    _loadLogbookTotals();
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

  Future<void> _loadLogbookTotals() async {
    if (_loadingTotals) return;
    setState(() {
      _loadingTotals = true;
      _totalsError = null;
    });
    try {
      final List<Entry> entries = await UserDatabaseHelper.db.getAllLogbook();
      final totals = _LogbookTotals();
      for (final e in entries) {
        totals.totalFlightTime += e.totalFlightTime;
        totals.pilotInCommand += e.pilotInCommand;
        totals.dualReceived += e.dualReceived;
        totals.soloTime += e.soloTime;
        totals.crossCountryTime += e.crossCountryTime;
        totals.dayTime += e.dayTime;
        totals.nightTime += e.nightTime;
        totals.actualInstruments += e.actualInstruments;
        totals.simulatedInstruments += e.simulatedInstruments;
        totals.dayLandings += e.dayLandings;
        totals.nightLandings += e.nightLandings;
        totals.instrumentApproaches += e.instrumentApproaches;
        totals.groundTime += e.groundTime;
        totals.flightSimulator += e.flightSimulator;
      }
      if (!mounted) return;
      setState(() {
        _logbookTotals = totals;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _totalsError = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingTotals = false;
      });
    }
  }

  Future<void> _ensureTotalsLoaded() async {
    if (_logbookTotals == null && !_loadingTotals) {
      await _loadLogbookTotals();
    }
  }

  String _fmtH(double h) => h.toStringAsFixed(1);

  String _formatTotalsSummary(_LogbookTotals t) {
    return "(total ${_fmtH(t.totalFlightTime)}, PIC ${_fmtH(t.pilotInCommand)}, dual ${_fmtH(t.dualReceived)}, solo ${_fmtH(t.soloTime)}, XC ${_fmtH(t.crossCountryTime)}, night ${_fmtH(t.nightTime)}, actual instrument ${_fmtH(t.actualInstruments)}, simulated instrument ${_fmtH(t.simulatedInstruments)}, day landings ${t.dayLandings}, night landings ${t.nightLandings}, instrument approaches ${t.instrumentApproaches})";
  }

  Future<String> _augmentQueryIfNeeded(String text) async {
    final lower = text.toLowerCase();
    final bool looksLikePplHoursQuery =
        (lower.contains('private pilot') || lower.contains('ppl')) &&
        (lower.contains('how many hours') || lower.contains('hours left') || lower.contains('hours do i have left') || lower.contains('how much time'));
    if (!looksLikePplHoursQuery) return text;

    await _ensureTotalsLoaded();
    final t = _logbookTotals;
    if (t == null || !t.hasData) return text;

    if (lower.contains('my current hours are')) return text; // already has context
    final summary = _formatTotalsSummary(t);
    return "$text, my current hours are $summary";
  }

  Future<String> _augmentWithSelectedCategory(String text) async {
    await _loadCategoryContext();
    final ctx = _categoryContext?.trim();
    if (ctx == null || ctx.isEmpty) return text;
    final label = _selectedCategory;
    if (text.toLowerCase().contains('context:')) return text; // basic guard to avoid duplication
    return "$text\nContext [$label]: $ctx";
  }

  void _onPplHoursLeft() async {
    await _ensureTotalsLoaded();
    final t = _logbookTotals;
    final base = "How many hours do I have left to get to private pilot certificate";
    final withTotals = (t != null && t.hasData) ? ", my current hours are ${_formatTotalsSummary(t)}" : "";
    final text = "$base$withTotals";
    setState(() {
      _inputController.text = text;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputController.text.length),
      );
    });
    _inputFocusNode.requestFocus();
  }

  void _appendTotalsToInput() async {
    await _ensureTotalsLoaded();
    final t = _logbookTotals;
    if (t == null || !t.hasData) {
      // If not available, try reloading
      await _loadLogbookTotals();
      return;
    }
    final snippet = "my current hours are ${_formatTotalsSummary(t)}";
    final current = _inputController.text.trim();
    final newText = current.isEmpty ? snippet : "$current, $snippet";
    setState(() {
      _inputController.text = newText;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputController.text.length),
      );
    });
    _inputFocusNode.requestFocus();
  }

  Widget _hoursChip(String label, double hours) {
    return Chip(label: Text('$label ${_fmtH(hours)}h'));
  }

  Widget _buildTotalsSummaryWidget(_LogbookTotals t) {
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 6, 0, 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _hoursChip('Total', t.totalFlightTime),
            _hoursChip('PIC', t.pilotInCommand),
            _hoursChip('Dual', t.dualReceived),
            _hoursChip('Solo', t.soloTime),
            _hoursChip('XC', t.crossCountryTime),
            _hoursChip('Night', t.nightTime),
            _hoursChip('Instr (act)', t.actualInstruments),
            _hoursChip('Instr (sim)', t.simulatedInstruments),
            Chip(label: Text('Landings D ${t.dayLandings} N ${t.nightLandings}')),
            Chip(label: Text('Approaches ${t.instrumentApproaches}')),
          ],
        ),
      ),
    );
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
              child: Text('Failed to load category: \'${_categoryError}\'', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
          if (_categoryContext != null && _categoryContext!.isNotEmpty) _buildCategorySummaryCard(_selectedCategory, _categoryContext!),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(label: const Text('PPL hours left'), onPressed: _onPplHoursLeft),
                const SizedBox(width: 8),
                ActionChip(label: const Text('Insert totals'), onPressed: _appendTotalsToInput),
                const SizedBox(width: 8),
                ActionChip(label: const Text('Insert context'), onPressed: () async {
                  await _loadCategoryContext();
                  if ((_categoryContext ?? '').isEmpty) return;
                  final current = _inputController.text.trim();
                  final snippet = 'Context [$_selectedCategory]: ${_categoryContext!}';
                  final newText = current.isEmpty ? snippet : '$current\n$snippet';
                  setState(() {
                    _inputController.text = newText;
                    _inputController.selection = TextSelection.fromPosition(TextPosition(offset: _inputController.text.length));
                  });
                  _inputFocusNode.requestFocus();
                }),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Refresh logbook totals',
                  onPressed: _loadingTotals ? null : _loadLogbookTotals,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (_loadingTotals) const LinearProgressIndicator(minHeight: 2),
          if (_totalsError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Failed to load totals: \'${_totalsError}\'', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
          if (_logbookTotals != null) _buildTotalsSummaryWidget(_logbookTotals!),
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
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Refresh category',
          onPressed: _loadingCategory ? null : _loadCategoryContext,
          icon: const Icon(Icons.autorenew),
        ),
        if (_loadingCategory) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
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
      _loadingCategory = true;
      _categoryError = null;
    });
    try {
      String ctx;
      switch (_selectedCategory) {
        case 'Logbook':
          await _ensureTotalsLoaded();
          final t = _logbookTotals;
          ctx = (t == null || !t.hasData) ? '' : _formatTotalsSummary(t);
          break;
        case 'Flight plan':
          ctx = await _summarizeFlightPlan();
          break;
        case 'Weather':
          ctx = _summarizeWeather();
          break;
        case 'Checklists':
          ctx = await _summarizeChecklists();
          break;
        case 'Weight & balance':
          ctx = await _summarizeWnb();
          break;
        case 'Aircraft':
          ctx = await _summarizeAircraft();
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
      if (!mounted) return;
      setState(() {
        _loadingCategory = false;
      });
    }
  }

  Future<String> _summarizeFlightPlan() async {
    final route = Storage().route;
    final all = route.getAllDestinations();
    final names = all.map((d) => d.locationID).toList();
    final tc = route.totalCalculations;
    if (names.isEmpty && tc == null) return '';
    String partRoute = names.isEmpty ? '' : 'route ${names.join(' ')}';
    String partCalc = '';
    if (tc != null) {
      final distNm = tc.distance.toStringAsFixed(1);
      final gs = tc.groundSpeed.toStringAsFixed(0);
      final timeMin = (tc.time).toStringAsFixed(0);
      final fuel = tc.fuel.toStringAsFixed(1);
      partCalc = 'distance ${distNm}nm, GS ${gs}kt, time ${timeMin}min, fuel ${fuel}gal';
    }
    return [partRoute, partCalc].where((s) => s.isNotEmpty).join('; ');
  }

  String _summarizeWeather() {
    try {
      final metars = Storage().metar.getAll().whereType<Metar>().toList();
      int vfr = 0, mvfr = 0, ifr = 0, lifr = 0;
      for (final m in metars) {
        switch (m.category) {
          case 'VFR': vfr++; break;
          case 'MVFR': mvfr++; break;
          case 'IFR': ifr++; break;
          case 'LIFR': lifr++; break;
        }
      }
      final tafs = Storage().taf.getAll();
      final tfrs = Storage().tfr.getAll();
      final aireps = Storage().airep.getAll();
      final asg = Storage().airSigmet.getAll();
      return 'METAR: VFR $vfr, MVFR $mvfr, IFR $ifr, LIFR $lifr; TAF ${tafs.length}; TFR ${tfrs.length}; AIREP ${aireps.length}; SIGMET/AIRMET ${asg.length}';
    } catch (_) {
      return '';
    }
  }

  Future<String> _summarizeChecklists() async {
    final lists = await UserDatabaseHelper.db.getAllChecklist();
    if (lists.isEmpty) return '';
    final active = Storage().activeChecklistName;
    final names = lists.map((c) => c.name).take(3).join(', ');
    final suffix = lists.length > 3 ? '…' : '';
    final head = active.isNotEmpty ? 'active $active; ' : '';
    return '${head}${lists.length} lists: $names$suffix';
  }

  Future<String> _summarizeWnb() async {
    final all = await UserDatabaseHelper.db.getAllWnb();
    if (all.isEmpty) return '';
    final names = all.map((w) => w.name).take(3).join(', ');
    final suffix = all.length > 3 ? '…' : '';
    return '${all.length} configs: $names$suffix';
  }

  Future<String> _summarizeAircraft() async {
    try {
      final acs = await UserDatabaseHelper.db.getAllAircraft();
      if (acs.isEmpty) return '';
      final names = acs.map((a) => a.tail).take(3).join(', ');
      final suffix = acs.length > 3 ? '…' : '';
      return '${acs.length} aircraft: $names$suffix';
    } catch (_) {
      return '';
    }
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
