import 'package:flutter/material.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/scheduler_repository.dart';
import 'scheduler_detail_screen.dart';

class SchedulerCreateScreen extends StatefulWidget {
  const SchedulerCreateScreen({super.key});

  @override
  State<SchedulerCreateScreen> createState() => _SchedulerCreateScreenState();
}

class _SchedulerCreateScreenState extends State<SchedulerCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _airportCtrl = TextEditingController();
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
      Toast.showToast(context, "Scheduler name must be at least 3 characters",
          const Icon(Icons.info, color: Colors.orange), 3);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await SchedulerRepository.instance.createGroup(
        name: name,
        description: _descCtrl.text.trim(),
        homeAirport: _airportCtrl.text.trim().isEmpty
            ? null
            : _airportCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SchedulerDetailScreen(groupId: id)),
      );
    } catch (e) {
      if (mounted) {
        Toast.showToast(context, "Could not create scheduler: $e",
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
        title: const Text("New Scheduler"),
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
                labelText: "Scheduler name",
                hintText: "e.g. KBED Flying Club, Skyhawk Partnership",
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
                hintText: "What's this scheduler for?",
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
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text("Private scheduler"),
                subtitle: const Text(
                    "All schedulers are private. Members find it by name and "
                    "you approve every join request. You can set booking "
                    "limits afterwards from the Rules screen."),
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
              label: const Text("Create Scheduler"),
            ),
          ],
        ),
      ),
    );
  }
}
