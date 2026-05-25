import 'package:flutter/material.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/community_repository.dart';
import 'models/pilot_profile.dart';

class ProfileEditScreen extends StatefulWidget {
  final PilotProfile profile;
  const ProfileEditScreen({super.key, required this.profile});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _airportCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _ratingsCtrl;
  late final TextEditingController _aircraftCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.displayName);
    _airportCtrl = TextEditingController(text: widget.profile.homeAirport ?? "");
    _bioCtrl = TextEditingController(text: widget.profile.bio ?? "");
    _ratingsCtrl = TextEditingController(text: widget.profile.ratings.join(", "));
    _aircraftCtrl =
        TextEditingController(text: widget.profile.aircraftTypes.join(", "));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _airportCtrl.dispose();
    _bioCtrl.dispose();
    _ratingsCtrl.dispose();
    _aircraftCtrl.dispose();
    super.dispose();
  }

  List<String> _splitCsv(String input) => input
      .split(",")
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      Toast.showToast(context, "Display name is required",
          const Icon(Icons.info, color: Colors.orange), 3);
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = widget.profile.copyWith(
        displayName: name,
        homeAirport: _airportCtrl.text.trim().isEmpty
            ? null
            : _airportCtrl.text.trim().toUpperCase(),
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        ratings: _splitCsv(_ratingsCtrl.text),
        aircraftTypes: _splitCsv(_aircraftCtrl.text),
      );
      await CommunityRepository.instance.saveMyProfile(updated);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      Toast.showToast(context, "Save failed: $e",
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
        title: const Text("Edit Profile"),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text("Save"),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameCtrl,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: "Display name",
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _airportCtrl,
              maxLength: 4,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: "Home airport (ICAO)",
                hintText: "e.g. KBED",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bioCtrl,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Bio (optional)",
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ratingsCtrl,
              decoration: const InputDecoration(
                labelText: "Ratings (comma separated)",
                hintText: "PPL, IFR, CFI",
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _aircraftCtrl,
              decoration: const InputDecoration(
                labelText: "Aircraft I fly (comma separated)",
                hintText: "C172, PA28, DA40",
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
      ),
    );
  }
}
