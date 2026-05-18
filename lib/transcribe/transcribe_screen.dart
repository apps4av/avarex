import 'package:avaremp/constants.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/transcribe/stt_backend.dart';
import 'package:avaremp/transcribe/transcribe_service.dart';
import 'package:avaremp/transcribe/voice_pack_section.dart';
import 'package:avaremp/transcribe/whisper_model_manager.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// View over [TranscribeService]. All recognizer state lives in the
/// singleton service, so leaving this screen does NOT stop transcription —
/// the recognizer keeps running across Map / Plate / Plan / Find. A small
/// global [TranscribeStatusOverlay] indicator on [MainScreen] reflects the
/// active state from any tab.
class TranscribeScreen extends StatefulWidget {
  const TranscribeScreen({super.key});

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> {
  final TranscribeService _svc = TranscribeService();
  final WhisperModelManager _mgr = WhisperModelManager();
  final ScrollController _scrollController = ScrollController();

  late final Listenable _listenable;
  late final VoidCallback _onChanged;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      _svc.isInitialized,
      _svc.isListening,
      _svc.isStarting,
      _svc.audioLevel,
      _svc.statusMessage,
      _svc.initError,
      _svc.partial,
      _svc.entries,
      _svc.activeEngine,
      _mgr.changes,
    ]);
    _onChanged = () {
      if (!mounted) return;
      setState(() {});
      _scrollToBottom();
    };
    _listenable.addListener(_onChanged);

    _svc.init();
    // Best-effort refresh of installed status — cheap on app start, this
    // here is for the case where the user installed/deleted a voice pack
    // since the screen was last open.
    _mgr.refreshAll();
  }

  @override
  void dispose() {
    _listenable.removeListener(_onChanged);
    _scrollController.dispose();
    // NOTE: We intentionally DO NOT stop the recognizer here. The service is
    // a singleton and outlives this screen so transcription continues across
    // screen navigation.
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _shareTranscript() async {
    if (!_svc.hasContent) {
      Toast.showToast(
        context,
        'Nothing to share yet',
        const Icon(Icons.info, color: Colors.amber),
        2,
      );
      return;
    }
    final buffer = StringBuffer();
    for (final e in _svc.entries.value) {
      buffer.writeln('[${_formatTime(e.timestamp)}] ${e.text}');
    }
    if (_svc.partial.value.isNotEmpty) {
      buffer.writeln('[partial] ${_svc.partial.value}');
    }
    try {
      await SharePlus.instance
          .share(ShareParams(text: buffer.toString().trimRight()));
    } catch (e) {
      if (!mounted) return;
      Toast.showToast(
        context,
        'Failed to share: $e',
        const Icon(Icons.error, color: Colors.red),
        3,
      );
    }
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}:${t.second.toString().padLeft(2, "0")}';

  Future<void> _onEnginePreferenceChanged(String pref) async {
    Storage().settings.setTranscribeEngine(pref);
    await _svc.reconfigure();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: Row(
          children: [
            Icon(MdiIcons.microphoneMessage, size: 24),
            const SizedBox(width: 8),
            const Text('Transcribe'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            tooltip: 'Engine preference',
            onSelected: _onEnginePreferenceChanged,
            itemBuilder: (context) {
              final current = Storage().settings.getTranscribeEngine();
              return [
                _engineMenuItem(
                  value: 'auto',
                  selected: current == 'auto',
                  title: 'Auto',
                  subtitle: 'Whisper if installed, else platform',
                ),
                _engineMenuItem(
                  value: 'platform',
                  selected: current == 'platform',
                  title: 'Platform (online)',
                  subtitle: 'iOS/Android speech recognizer',
                ),
                _engineMenuItem(
                  value: 'whisper',
                  selected: current == 'whisper',
                  title: 'Whisper (offline AI)',
                  subtitle: 'Requires voice pack download',
                ),
              ];
            },
          ),
          const Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            showDuration: Duration(seconds: 30),
            message:
                'Live speech-to-text — primarily for transcribing ATC audio that you hear in your aviation headset.\n\nRecommended setup:\n1. Connect the headset audio output (or an aviation audio splitter / panel-mounted audio tap) to your phone\'s audio input via a 3.5 mm TRRS cable.\n2. On phones without a 3.5 mm jack, use a USB-C or Lightning audio adapter.\n3. The phone treats the headset audio as a normal microphone input — no Bluetooth or extra pairing required.\n\nEngines:\n• Auto / Platform — uses the OS speech recognizer (usually needs internet on Android).\n• Whisper (offline AI) — runs an on-device model that is more robust to ATC accents and engine noise. Tap the AI Voice Pack section below to install it.\n\nTranscription keeps running when you switch to Map / Plate / Plan / Find — a small mic indicator at the top of the main screen lets you stop or return here at any time.',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.help_outline),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(scheme),
            // Voice-pack manager lives directly on this screen so the pilot
            // never has to leave Transcribe to enable offline AI. The widget
            // is a self-contained ExpansionTile; it auto-collapses once a
            // pack is installed and expands by default when nothing is.
            if (_shouldShowVoicePackSection()) const VoicePackSection(),
            Expanded(child: _buildTranscriptArea(scheme)),
            _buildControls(scheme),
          ],
        ),
      ),
    );
  }

  /// Hide the voice-pack section only when the user has explicitly chosen
  /// the platform engine *and* no model is installed; otherwise we always
  /// show it (so installed packs can be inspected/deleted, and so users in
  /// 'auto'/'whisper' modes can install one inline).
  bool _shouldShowVoicePackSection() {
    final pref = Storage().settings.getTranscribeEngine();
    if (pref == 'platform' && !_mgr.isAnyInstalled()) return false;
    return true;
  }

  PopupMenuItem<String> _engineMenuItem({
    required String value,
    required bool selected,
    required String title,
    required String subtitle,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme scheme) {
    final listening = _svc.isListening.value;
    final initError = _svc.initError.value;
    final level = _svc.audioLevel.value;
    // While listening, derive the header word from the live audio level so
    // the label actually tracks speech instead of just mirroring the mic
    // open/closed flag. -38 dBFS is the same threshold the Whisper backend
    // uses for VAD onset, so this header lines up with what the recognizer
    // is doing.
    final bool hearingSpeech = listening && level > -38.0;
    final statusColor = listening
        ? (hearingSpeech ? Colors.green : scheme.outline)
        : (initError != null ? Colors.red : scheme.outline);
    final headerText = listening
        ? (hearingSpeech ? 'Hearing speech' : 'Quiet')
        : (initError ?? 'Idle — tap microphone to start');
    final engineChip = _engineChip(scheme);
    final statusLine = _svc.statusMessage.value;
    final showStatusLine =
        statusLine.isNotEmpty && statusLine != 'Idle' && statusLine != 'Stopped';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: scheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                listening ? Icons.mic : Icons.mic_off,
                size: 18,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headerText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              if (engineChip != null) engineChip,
            ],
          ),
          if (listening) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: _audioLevelToBar(level),
              minHeight: 4,
            ),
          ],
          // Always render the per-chunk diagnostic line (silence / inference
          // timing / duplicate / filtered) - while listening AND when
          // stopped - so the user can see what the recognizer most recently
          // did instead of just an unchanging top-level label.
          if (showStatusLine) ...[
            const SizedBox(height: 4),
            Text(
              statusLine,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ],
      ),
    );
  }

  /// Convert the backend's level (either dBFS [-160..0] from `record` or
  /// the platform recognizer's raw -2..10) into a 0..1 progress bar value.
  double _audioLevelToBar(double v) {
    if (v <= -1.5) {
      // dBFS path: -60 dBFS → 0, 0 dBFS → 1.
      final clamped = v.clamp(-60.0, 0.0);
      return (clamped + 60) / 60;
    }
    // speech_to_text path: -2..10.
    final clamped = v.clamp(-2.0, 10.0);
    return (clamped + 2) / 12;
  }

  /// Small badge in the top-right corner of the status bar indicating
  /// which engine is active. Hidden until [TranscribeService.init] has
  /// settled on a backend.
  Widget? _engineChip(ColorScheme scheme) {
    final engine = _svc.activeEngine.value;
    if (engine == null) return null;
    final label = engine == SttEngine.whisper ? 'AI' : 'OS';
    final tooltip = engine == SttEngine.whisper
        ? 'Offline AI (Whisper)'
        : 'Platform speech recognizer';
    final color = engine == SttEngine.whisper ? Colors.deepPurple : scheme.primary;
    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(40),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildTranscriptArea(ColorScheme scheme) {
    final entries = _svc.entries.value;
    final partial = _svc.partial.value;
    if (entries.isEmpty && partial.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(MdiIcons.microphoneOutline,
                  size: 64, color: scheme.outline),
              const SizedBox(height: 16),
              Text(
                _svc.isInitialized.value
                    ? 'Tap the microphone to start.\nEverything heard will be transcribed here.\nTranscription continues across screens.'
                    : (_svc.initError.value ?? 'Initializing…'),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      color: scheme.surface,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: entries.length + (partial.isEmpty ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i < entries.length) {
            final entry = entries[i];
            return _buildBubble(
              scheme,
              entry.text,
              _formatTime(entry.timestamp),
              isPartial: false,
            );
          }
          return _buildBubble(
            scheme,
            partial,
            'listening…',
            isPartial: true,
          );
        },
      ),
    );
  }

  Widget _buildBubble(ColorScheme scheme, String text, String time,
      {required bool isPartial}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPartial
            ? scheme.primaryContainer.withAlpha(60)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPartial
              ? scheme.primary.withAlpha(80)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            text,
            style: TextStyle(
              fontSize: 15,
              fontStyle: isPartial ? FontStyle.italic : FontStyle.normal,
              color: isPartial
                  ? scheme.onSurface.withAlpha(180)
                  : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: TextStyle(fontSize: 10, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ColorScheme scheme) {
    final listening = _svc.isListening.value;
    final starting = _svc.isStarting.value;
    final initialized = _svc.isInitialized.value;
    final hasContent = _svc.hasContent;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filledTonal(
                onPressed: hasContent ? _svc.clear : null,
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Clear transcript',
              ),
              SizedBox(
                width: 76,
                height: 76,
                child: FloatingActionButton.large(
                  heroTag: 'transcribe_mic',
                  onPressed: !initialized || starting
                      ? null
                      : (listening ? _svc.stop : _svc.start),
                  backgroundColor:
                      listening ? Colors.red : scheme.primary,
                  child: starting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Icon(
                          listening ? Icons.stop : Icons.mic,
                          color: Colors.white,
                          size: 32,
                        ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: hasContent ? _shareTranscript : null,
                icon: const Icon(Icons.share),
                tooltip: 'Share transcript',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
