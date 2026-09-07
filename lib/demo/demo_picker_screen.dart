import 'package:flutter/material.dart';

import 'demo_engine.dart';
import 'demo_registry.dart';
import 'demo_tour.dart';

/// List of registered tours plus Play all.
class DemoPickerScreen extends StatelessWidget {
  const DemoPickerScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DemoPickerScreen()),
    );
  }

  Future<void> _start(BuildContext context, Future<void> Function() play) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await play();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch Demo'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Text(
            'The app presses the real buttons and speaks what each control does. Pause, skip, or exit anytime.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: const Icon(Icons.playlist_play),
              ),
              title: const Text('Play all'),
              subtitle: const Text('Map, plan, find, notes, takeoff, and tiles — in order'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _start(context, DemoEngine.instance.playAll),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'TOPICS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          for (final DemoTour tour in DemoRegistry.tours)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: const Icon(Icons.play_circle_outline),
                ),
                title: Text(tour.title),
                subtitle: Text(tour.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _start(context, () => DemoEngine.instance.playTour(tour)),
              ),
            ),
        ],
      ),
    );
  }
}
