class Checklist {
  final String name;
  final String aircraft;
  final List<String> steps;

  Checklist(this.name, this.aircraft, this.steps);

  factory Checklist.empty() {
    return Checklist("", "", []);
  }
}