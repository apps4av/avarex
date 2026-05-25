import 'package:flutter/material.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/community_repository.dart';
import 'group_detail_screen.dart';
import 'models/pilot_group.dart';

class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _airportCtrl = TextEditingController();
  GroupVisibility _visibility = GroupVisibility.public;
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _airportCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 3) {
      Toast.showToast(context, "Group name must be at least 3 characters",
          const Icon(Icons.info, color: Colors.orange), 3);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await CommunityRepository.instance.createGroup(
        name: name,
        description: _descCtrl.text.trim(),
        visibility: _visibility,
        homeAirport: _airportCtrl.text.trim().isEmpty
            ? null
            : _airportCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: id)),
      );
    } catch (e) {
      Toast.showToast(context, "Could not create group: $e",
          const Icon(Icons.error, color: Colors.red), 4);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("New Group"),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameCtrl,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: "Group name",
                hintText: "e.g. KBED Pilots, Vintage Cessna Owners",
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLength: 280,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Description",
                hintText: "What's this group about?",
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _airportCtrl,
              maxLength: 4,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: "Home airport (optional)",
                hintText: "ICAO, e.g. KBED",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Visibility",
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    RadioGroup<GroupVisibility>(
                      groupValue: _visibility,
                      onChanged: (v) =>
                          setState(() => _visibility = v ?? _visibility),
                      child: const Column(
                        children: [
                          RadioListTile<GroupVisibility>(
                            contentPadding: EdgeInsets.zero,
                            value: GroupVisibility.public,
                            title: Text("Public"),
                            subtitle: Text(
                                "Anyone can find this group and join immediately."),
                          ),
                          RadioListTile<GroupVisibility>(
                            contentPadding: EdgeInsets.zero,
                            value: GroupVisibility.private,
                            title: Text("Private"),
                            subtitle: Text(
                                "Group is discoverable, but you approve every new member."),
                            secondary: Icon(Icons.lock_outline),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text("Create Group"),
            ),
          ],
        ),
      ),
    );
  }
}
