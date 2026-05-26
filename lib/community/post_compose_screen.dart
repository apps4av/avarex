import 'package:flutter/material.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/community_repository.dart';

class PostComposeScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const PostComposeScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<PostComposeScreen> createState() => _PostComposeScreenState();
}

class _PostComposeScreenState extends State<PostComposeScreen> {
  final _textCtrl = TextEditingController();
  final _airportCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _airportCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      Toast.showToast(context, "Type something first",
          const Icon(Icons.info, color: Colors.orange), 2);
      return;
    }
    setState(() => _busy = true);
    try {
      await CommunityRepository.instance.createPost(
        widget.groupId,
        text: text,
        attachedAirport: _airportCtrl.text.trim().isEmpty
            ? null
            : _airportCtrl.text.trim(),
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: Text("Post to ${widget.groupName}"),
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
            label: const Text("Post"),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _textCtrl,
                maxLength: 1000,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "Share something with the group...",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }
}
