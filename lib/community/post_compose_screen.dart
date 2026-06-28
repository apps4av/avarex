import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';
import 'package:image_picker/image_picker.dart';

import '../constants.dart';
import '../storage.dart';
import '../utils/toast.dart';
import 'data/community_repository.dart';
import 'models/group_post.dart';

class PostComposeScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  /// When set, this compose screen creates a reply attached to the topic
  /// with this id instead of a new top-level topic. Reply mode hides the
  /// airport / flight-plan attachments to keep replies conversational.
  final String? replyToId;

  /// Author of the topic being replied to, shown in the app bar so the
  /// user knows which conversation they're adding to.
  final String? replyToAuthorName;

  const PostComposeScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.replyToId,
    this.replyToAuthorName,
  });

  bool get isReply => replyToId != null;

  @override
  State<PostComposeScreen> createState() => _PostComposeScreenState();
}

class _PostComposeScreenState extends State<PostComposeScreen> {
  final _textCtrl = TextEditingController();
  final _airportCtrl = TextEditingController();
  final _picker = ImagePicker();

  String? _attachedRouteText;
  String? _attachedRouteName;
  final List<Uint8List> _images = [];
  bool _busy = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _airportCtrl.dispose();
    super.dispose();
  }

  void _attachCurrentPlan() {
    final route = Storage().route;
    final asString = route.toString().trim();
    if (asString.isEmpty) {
      Toast.showToast(
        context,
        "Your active flight plan is empty.",
        const Icon(Icons.info, color: Colors.orange),
        2,
      );
      return;
    }
    setState(() {
      _attachedRouteText = asString;
      _attachedRouteName = route.name;
    });
  }

  void _clearPlan() {
    setState(() {
      _attachedRouteText = null;
      _attachedRouteName = null;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= GroupPost.maxImages) {
      Toast.showToast(
        context,
        "Maximum ${GroupPost.maxImages} photos per post.",
        const Icon(Icons.info, color: Colors.orange),
        2,
      );
      return;
    }
    try {
      // maxWidth + imageQuality keep uploads small (~200-400KB typical),
      // which also strips EXIF for privacy.
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() => _images.add(bytes));
    } catch (e) {
      if (mounted) {
        Toast.showToast(
          context,
          "Could not load photo: $e",
          const Icon(Icons.error, color: Colors.red),
          3,
        );
      }
    }
  }

  void _showImageSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text("Choose from gallery"),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text("Take a photo"),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final text = _textCtrl.text.trim();
    final isReply = widget.isReply;
    final hasContent = isReply
        ? (text.isNotEmpty || _images.isNotEmpty)
        : (text.isNotEmpty || _images.isNotEmpty || _attachedRouteText != null);
    if (!hasContent) {
      Toast.showToast(
          context,
          isReply ? "Write a reply or add a photo first"
              : "Add text, a photo, or a plan first",
          const Icon(Icons.info, color: Colors.orange),
          2);
      return;
    }
    setState(() => _busy = true);
    try {
      await CommunityRepository.instance.createPost(
        widget.groupId,
        text: text,
        attachedAirport: isReply || _airportCtrl.text.trim().isEmpty
            ? null
            : _airportCtrl.text.trim(),
        attachedRouteText: isReply ? null : _attachedRouteText,
        attachedRouteName: isReply ? null : _attachedRouteName,
        images: List<Uint8List>.from(_images),
        replyToId: widget.replyToId,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Toast.showToast(context, "Post failed: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReply = widget.isReply;
    final title = isReply
        ? (widget.replyToAuthorName?.isNotEmpty == true
            ? "Reply to ${widget.replyToAuthorName}"
            : "Reply")
        : "Post to ${widget.groupName}";
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: Text(title),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(isReply ? "Reply" : "Post"),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(
                        controller: _textCtrl,
                        maxLength: 1000,
                        maxLines: null,
                        minLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: isReply
                              ? "Write a reply..."
                              : "Share something with the group...",
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_images.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _imageStrip(),
                      ],
                      if (_attachedRouteText != null) ...[
                        const SizedBox(height: 8),
                        _planChip(),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 16),
              if (!isReply) ...[
                TextField(
                  controller: _airportCtrl,
                  maxLength: 4,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: "Attach airport (optional)",
                    hintText: "ICAO, e.g. KBED",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _showImageSource,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text("Photo (${_images.length}/${GroupPost.maxImages})"),
                  ),
                  if (!isReply) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _attachedRouteText == null
                          ? _attachCurrentPlan
                          : null,
                      icon: const Icon(Icons.route),
                      label: const Text("Attach plan"),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageStrip() {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _images[i],
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _images.removeAt(i)),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _planChip() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.route, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _attachedRouteName?.isNotEmpty == true
                      ? _attachedRouteName!
                      : "Attached plan",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _attachedRouteText!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _clearPlan,
            icon: Icon(MdiIcons.closeCircleOutline, size: 18),
            tooltip: "Remove plan",
            color: scheme.onSecondaryContainer,
          ),
        ],
      ),
    );
  }
}
