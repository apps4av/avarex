class Checklist {
  String name;
  String aircraft;
  List<String> steps;

  Checklist(this.name, this.aircraft, this.steps);


  factory Checklist.empty() {
    return Checklist("", "", []);
  }
}