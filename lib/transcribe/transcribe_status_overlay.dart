import 'package:avaremp/transcribe/stt_backend.dart';
import 'package:avaremp/transcribe/transcribe_service.dart';
import 'package:flutter/material.dart';

/// Small floating pill that surfaces transcription state across the four
/// main tabs (Map / Plate / Plan / Find). Invisible when transcription is
/// idle. While listening:
///
///   * Tap the pill body → navigate to the Transcribe screen.
///   * Tap the close icon → stop the recognizer globally (release the
///     wake-lock, etc).
///
/// Designed to occupy a top-right corner with minimal real-estate so it
/// doesn't obscure the chart or instruments.
class TranscribeStatusOverlay extends StatelessWidget {
  const TranscribeStatusOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // Positioned MUST be a direct child of Stack, so it is always returned
    // here and the visibility is decided inside via the listenables.
    return Positioned(
      top: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
          child: _PillVisibility(),
        ),
      ),
    );
  }
}

/// Decides whether the pill is shown, and forwards the starting flag to the
/// pill. Lives below the SafeArea so that the parent's [Positioned] is the
/// direct child of the [Stack] (a hard Flutter requirement).
class _PillVisibility extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final svc = TranscribeService();
    return ListenableBuilder(
      listenable: Listenable.merge(
          [svc.isListening, svc.isStarting, svc.activeEngine]),
      builder: (context, _) {
        final listening = svc.isListening.value;
        final starting = svc.isStarting.value;
        if (!listening && !starting) {
          return const SizedBox.shrink();
        }
        return _Pill(starting: starting);
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final bool starting;

  const _Pill({required this.starting});

  @override
  Widget build(BuildContext context) {
    final svc = TranscribeService();
    // Surface which engine is active so the pilot can tell at a glance
    // whether they're on online platform STT (no badge) or offline Whisper
    // ("AI" badge). Whisper-active pill stays red but gains a small label.
    final engine = svc.activeEngine.value;
    final isWhisper = engine == SttEngine.whisper;
    final label = starting
        ? 'Starting…'
        : (isWhisper ? 'REC · AI' : 'REC');
    return Material(
      color: Colors.red.withAlpha(220),
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.pushNamed(context, '/transcribe'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (starting)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const _BlinkingDot(),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: 'Stop transcription',
                child: InkWell(
                  onTap: starting ? null : svc.stop,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: starting
                          ? Colors.white.withAlpha(120)
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_ctrl),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
