import 'package:avaremp/constants.dart';
import 'package:avaremp/transcribe/transcribe_service.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// View over [TranscribeService]. All recognizer / Bluetooth state lives in
/// the singleton service, so leaving this screen does NOT stop transcription
/// — the recognizer keeps running across Map / Plate / Plan / Find. A small
/// global [TranscribeStatusOverlay] indicator on [MainScreen] reflects the
/// active state from any tab.
class TranscribeScreen extends StatefulWidget {
  const TranscribeScreen({super.key});

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> {
  final TranscribeService _svc = TranscribeService();
  final ScrollController _scrollController = ScrollController();

  late final Listenable _listenable;
  late final VoidCallback _onChanged;

  @override
  void initState() {
    super.initState();

    // Re-paint on any service state change.
    _listenable = Listenable.merge([
      _svc.isInitialized,
      _svc.isListening,
      _svc.isStarting,
      _svc.audioLevel,
      _svc.statusMessage,
      _svc.initError,
      _svc.partial,
      _svc.entries,
      _svc.usingOnDevice,
    ]);
    _onChanged = () {
      if (!mounted) return;
      setState(() {});
      _scrollToBottom();
    };
    _listenable.addListener(_onChanged);

    // Idempotent — ensures permissions/recognizer are wired up on first open.
    _svc.init();
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
        actions: const [
          Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            showDuration: Duration(seconds: 30),
            message:
                'Live speech-to-text — primarily for transcribing ATC audio that you hear in your aviation headset.\n\nRecommended setup:\n1. Connect the headset audio output (or an aviation audio splitter / panel-mounted audio tap) to your phone\'s audio input via a 3.5 mm TRRS cable.\n2. On phones without a 3.5 mm jack, use a USB-C or Lightning audio adapter.\n3. The phone treats the headset audio as a normal microphone input — no Bluetooth or extra pairing required.\n\nIf nothing is wired in, the phone\'s built-in microphone is used as a fallback (quality is poor in a typical cockpit due to engine and slipstream noise).\n\nTranscription keeps running when you switch to Map / Plate / Plan / Find — a small mic indicator at the top of the main screen lets you stop or return here at any time.\n\nOffline use:\nTranscribe prefers the on-device speech recognizer so it works without cell coverage.\n• iPhone: on-device English recognition is available on most devices running iOS 13+.\n• Android: install an offline speech model first via Settings → System → Languages → On-device speech recognition (or Voice Input settings) and choose English. Without an installed pack, Android falls back to Google\'s network recognizer, which will not work in the air.\n\nThe status bar shows "On-device" or "Network" so you know which one is in use.',
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
            Expanded(child: _buildTranscriptArea(scheme)),
            _buildControls(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme scheme) {
    final listening = _svc.isListening.value;
    final initError = _svc.initError.value;
    final statusColor = listening
        ? Colors.green
        : (initError != null ? Colors.red : scheme.outline);
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
                  listening
                      ? 'Listening'
                      : (initError ?? 'Idle — tap microphone to start'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              if (listening) _buildModeBadge(scheme),
            ],
          ),
          if (listening) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: ((_svc.audioLevel.value.clamp(-2.0, 10.0)) + 2) / 12,
              minHeight: 4,
            ),
          ],
          if (!listening &&
              _svc.statusMessage.value.isNotEmpty &&
              _svc.statusMessage.value != 'Idle') ...[
            const SizedBox(height: 4),
            Text(
              _svc.statusMessage.value,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeBadge(ColorScheme scheme) {
    final onDevice = _svc.usingOnDevice.value;
    final label = onDevice ? 'On-device' : 'Network';
    final color = onDevice ? Colors.green : Colors.orange;
    return Tooltip(
      message: onDevice
          ? 'Speech recognition is running on this device — works without internet.'
          : 'Speech recognition is going through the platform\'s network recognizer — requires internet. On Android, install an offline speech pack to enable on-device recognition.',
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(40),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(140)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              onDevice ? Icons.offline_bolt : Icons.cloud_outlined,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.4,
              ),
            ),
          ],
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
