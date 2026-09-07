/// One action in a [DemoTour] step list.
sealed class DemoStep {
  const DemoStep();
}

/// Show [text] without tapping anything.
class Narrate extends DemoStep {
  final String text;
  final Duration hold;

  const Narrate(this.text, {this.hold = const Duration(milliseconds: 2600)});
}

/// Highlight [targetId], move the pointer, and dispatch a real tap.
class Tap extends DemoStep {
  final String targetId;
  final String? caption;
  final Duration timeout;
  final Duration after;

  const Tap(
    this.targetId, {
    this.caption,
    this.timeout = const Duration(seconds: 4),
    this.after = const Duration(milliseconds: 700),
  });
}

/// Pause so the user can look at what just opened.
class Wait extends DemoStep {
  final Duration duration;

  const Wait(this.duration);

  factory Wait.seconds(int seconds) => Wait(Duration(seconds: seconds));
}

/// Switch the main bottom tab. Indices match [MainScreenState] tab constants.
class GoTab extends DemoStep {
  final int index;
  final String? caption;

  const GoTab._(this.index, {this.caption});

  static const int mapIndex = 0;
  static const int plateIndex = 1;
  static const int planIndex = 2;
  static const int findIndex = 3;

  static const GoTab map = GoTab._(mapIndex);
  static const GoTab plate = GoTab._(plateIndex);
  static const GoTab plan = GoTab._(planIndex);
  static const GoTab find = GoTab._(findIndex);

  const GoTab.mapWith({String? caption}) : this._(mapIndex, caption: caption);
  const GoTab.plateWith({String? caption}) : this._(plateIndex, caption: caption);
  const GoTab.planWith({String? caption}) : this._(planIndex, caption: caption);
  const GoTab.findWith({String? caption}) : this._(findIndex, caption: caption);
}

/// Type into a text field wrapped in a [DemoTarget].
class TypeText extends DemoStep {
  final String targetId;
  final String text;
  final String Function()? textOf;
  final String? caption;
  final Duration timeout;

  const TypeText(
    this.targetId,
    this.text, {
    this.textOf,
    this.caption,
    this.timeout = const Duration(seconds: 4),
  });

  String resolved() => textOf?.call() ?? text;
}

/// Pop the current route (drawer, overlay, named screen, destination popup).
class Pop extends DemoStep {
  final Duration after;

  const Pop({this.after = const Duration(milliseconds: 400)});
}

/// Run setup/teardown code (plan snapshot, pick sample airports, …).
class Prepare extends DemoStep {
  final Future<void> Function() run;

  const Prepare(this.run);
}
