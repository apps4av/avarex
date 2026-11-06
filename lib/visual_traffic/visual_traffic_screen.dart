import 'package:avaremp/visual_traffic/camera_view.dart';
import 'package:avaremp/visual_traffic/viewer_view.dart';
import 'package:flutter/material.dart';

/// Start page for Visual Traffic. One phone looks out the window and finds
/// aircraft. A second phone can show that phone's picture over Link.
class VisualTrafficScreen extends StatelessWidget {
  const VisualTrafficScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Visual Traffic")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Traffic awareness aid only. It will miss aircraft and it will box things that are not aircraft. It is not for collision avoidance. Always keep looking outside.",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Choice(
              icon: Icons.videocam,
              title: "This phone is the camera",
              body:
                  "Mount it so the camera sees out the windshield. A red box marks a moving target the model calls an airplane. A thin yellow box marks a small mover it is not sure about.",
              onTap: () => _open(context, const VisualTrafficCameraView()),
            ),
            const SizedBox(height: 12),
            _Choice(
              icon: Icons.tv,
              title: "Show another phone's camera",
              body:
                  "Shows the picture and boxes from a camera phone on the same Wi-Fi, and beeps when it finds a new airplane. Both phones need AvareX open.",
              onTap: () => _open(context, const VisualTrafficViewerView()),
            ),
            const SizedBox(height: 16),
            const Text(
              "Tips: put the phone where it sees the sky and the horizon. Keep the windshield clean and the phone off the glare. The phone gets warm, so keep it out of direct sun or plug it in. Set the camera field of view in the settings on the camera screen.",
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(body, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
