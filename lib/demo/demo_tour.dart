import 'demo_step.dart';

/// A named, playable sequence of [DemoStep]s.
class DemoTour {
  final String id;
  final String title;
  final String subtitle;
  final List<DemoStep> steps;

  const DemoTour({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.steps,
  });
}
