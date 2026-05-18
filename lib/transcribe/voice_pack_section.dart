import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'transcribe_service.dart';
import 'whisper_model_manager.dart';

/// In-screen voice-pack control surface for the Transcribe screen.
///
/// Direct-action UX (no two-step queue): tapping an "absent" row starts the
/// download immediately, tapping an in-flight download cancels it, tapping
/// an installed row prompts to delete. This stays out of the way (single
/// compact card) until the user expands it.
class VoicePackSection extends StatefulWidget {
  const VoicePackSection({super.key});

  @override
  State<VoicePackSection> createState() => _VoicePackSectionState();
}

class _VoicePackSectionState extends State<VoicePackSection> {
  final WhisperModelManager _mgr = WhisperModelManager();
  late final VoidCallback _onChanged;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _onChanged = () {
      if (mounted) setState(() {});
    };
    _mgr.changes.addListener(_onChanged);
    _mgr.refreshAll();
    // Auto-expand when nothing is installed yet so first-time users see
    // the options without having to hunt for them.
    _expanded = !_mgr.isAnyInstalled();
  }

  @override
  void dispose() {
    _mgr.changes.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _confirmDelete(WhisperVoicePackVariant variant) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete voice pack?'),
        content: Text(
          '${variant.displayName} (~${variant.approxSizeMb} MB) will be removed. '
          'You can re-download it any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _mgr.delete(variant.model);
    // ignore: unawaited_futures
    TranscribeService().reconfigure();
  }

  Future<void> _onRowTap(WhisperVoicePackVariant variant) async {
    final state = _mgr.stateOf(variant.model);
    switch (state) {
      case WhisperModelState.absentIdle:
        // Fire-and-forget; status pill on the row reflects progress.
        // ignore: unawaited_futures
        _startDownload(variant);
        break;
      case WhisperModelState.downloading:
        _mgr.cancelDownload(variant.model);
        break;
      case WhisperModelState.presentIdle:
        await _confirmDelete(variant);
        break;
      case WhisperModelState.deleting:
        // No-op while delete is in flight.
        break;
    }
  }

  Future<void> _startDownload(WhisperVoicePackVariant variant) async {
    await _mgr.download(variant.model);
    // After a successful install the service may want to hot-swap the
    // backend to Whisper. `reconfigure` is a no-op if the active engine
    // already matches the user preference.
    // ignore: unawaited_futures
    TranscribeService().reconfigure();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anyInstalled = _mgr.isAnyInstalled();
    final activeOps = _mgr.activeOperationCount();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Theme(
        // Hide the default ExpansionTile divider.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          leading: Icon(
            MdiIcons.brain,
            color: anyInstalled ? Colors.green : scheme.primary,
          ),
          title: Text(
            'AI Voice Pack',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          subtitle: Text(
            _headerSubtitle(anyInstalled, activeOps),
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          children: [
            for (final variant in kWhisperVoicePackVariants)
              _buildRow(variant, scheme),
            _buildImportRow(scheme),
          ],
        ),
      ),
    );
  }

  String _headerSubtitle(bool anyInstalled, int activeOps) {
    if (activeOps > 0) {
      return 'Installing voice pack…';
    }
    if (anyInstalled) {
      return 'Offline transcription enabled. Tap to manage.';
    }
    return 'Optional — adds higher-quality offline ATC transcription.';
  }

  Widget _buildRow(WhisperVoicePackVariant variant, ColorScheme scheme) {
    final state = _mgr.stateOf(variant.model);
    final progress = _mgr.progressPercent(variant.model);
    final installed = state == WhisperModelState.presentIdle;
    final downloading = state == WhisperModelState.downloading;
    final deleting = state == WhisperModelState.deleting;
    final isRecommended = variant.model.modelName == 'tiny.en';

    final bgColor = downloading
        ? Colors.blue.withAlpha(20)
        : deleting
            ? Colors.red.withAlpha(20)
            : null;
    final borderColor = downloading
        ? Colors.blue.withAlpha(120)
        : deleting
            ? Colors.red.withAlpha(120)
            : (installed ? Colors.green.withAlpha(120) : scheme.outlineVariant);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        dense: true,
        leading: _leadingIcon(state),
        title: Row(
          children: [
            Flexible(
              child: Text(
                variant.displayName,
                style: TextStyle(
                  fontWeight: installed || downloading
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
            if (isRecommended) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.primary.withAlpha(120)),
                ),
                child: Text(
                  'recommended',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          _rowSubtitle(variant, state, progress),
          style: TextStyle(fontSize: 11, color: scheme.outline),
        ),
        trailing: _trailing(state, progress),
        onTap: () => _onRowTap(variant),
      ),
    );
  }

  String _rowSubtitle(
    WhisperVoicePackVariant variant,
    WhisperModelState state,
    int progress,
  ) {
    switch (state) {
      case WhisperModelState.downloading:
        return 'Downloading $progress% · tap to cancel';
      case WhisperModelState.deleting:
        return 'Deleting…';
      case WhisperModelState.presentIdle:
        return 'Installed · tap to delete';
      case WhisperModelState.absentIdle:
        return '~${variant.approxSizeMb} MB · ${variant.description}';
    }
  }

  Widget? _leadingIcon(WhisperModelState state) {
    switch (state) {
      case WhisperModelState.presentIdle:
        return const Icon(Icons.check_circle, color: Colors.green, size: 22);
      case WhisperModelState.downloading:
        return const Icon(Icons.download, color: Colors.blue, size: 22);
      case WhisperModelState.deleting:
        return const Icon(Icons.delete, color: Colors.red, size: 22);
      case WhisperModelState.absentIdle:
        return const Icon(Icons.cloud_download_outlined,
            color: Colors.grey, size: 22);
    }
  }

  Widget _trailing(WhisperModelState state, int progress) {
    switch (state) {
      case WhisperModelState.downloading:
        return SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress / 100,
                strokeWidth: 3,
              ),
              const Icon(Icons.close, size: 18),
            ],
          ),
        );
      case WhisperModelState.deleting:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.red),
        );
      case WhisperModelState.presentIdle:
        return const Icon(Icons.delete_outline,
            color: Colors.redAccent, size: 22);
      case WhisperModelState.absentIdle:
        return const Icon(Icons.download_outlined, size: 22);
    }
  }

  /// Compact row pinned under the variant list that opens a file picker so
  /// the user can sideload a `.bin` they trained themselves (see
  /// `tools/whisper-atc/`). Disabled while any download/delete is in flight
  /// to keep the manager's per-slot state-machine well-defined.
  Widget _buildImportRow(ColorScheme scheme) {
    final busy = _mgr.activeOperationCount() > 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant,
          style: BorderStyle.solid,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.file_open_outlined,
          color: busy ? scheme.outline : scheme.primary,
          size: 22,
        ),
        title: Text(
          'Import from file…',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: busy ? scheme.outline : scheme.onSurface,
          ),
        ),
        subtitle: Text(
          'Sideload a fine-tuned ggml-*.bin you produced from tools/whisper-atc.',
          style: TextStyle(fontSize: 11, color: scheme.outline),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: busy ? null : _importFromFile,
      ),
    );
  }

  Future<void> _importFromFile() async {
    final variant = await _pickSlotDialog();
    if (variant == null || !mounted) return;

    // If the slot is already filled, confirm before clobbering it.
    if (_mgr.stateOf(variant.model) == WhisperModelState.presentIdle) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace existing voice pack?'),
          content: Text(
            '${variant.displayName} is already installed. Importing will '
            'overwrite the existing file.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      dialogTitle: 'Pick ggml-${variant.model.modelName}.bin',
      withData: false,
      withReadStream: false,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final path = picked.files.single.path;
    if (path == null) {
      _showSnack('Could not read the selected file path.');
      return;
    }

    try {
      await _mgr.importFromFile(variant.model, path);
      if (!mounted) return;
      _showSnack('${variant.displayName} installed.');
      // ignore: unawaited_futures
      TranscribeService().reconfigure();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Import failed: $e');
    }
  }

  Future<WhisperVoicePackVariant?> _pickSlotDialog() async {
    return showDialog<WhisperVoicePackVariant>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Install into which slot?'),
        children: [
          for (final v in kWhisperVoicePackVariants)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, v),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${v.displayName}  (ggml-${v.model.modelName}.bin)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      v.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(ctx).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
