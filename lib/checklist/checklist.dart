import 'dart:convert';

class Checklist {
  final String name;
  final String aircraft;
  final List<String> steps;

  Checklist(this.name, this.aircraft, this.steps);

  factory Checklist.empty() {
    return Checklist("", "", []);
  }

  factory Checklist.fromMap(Map<String, dynamic> map) {
    return Checklist(
      map['name'] as String,
      map['aircraft'] as String,
      List<String>.from(jsonDecode(map['items'] as String))
    );
  }

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'aircraft': aircraft,
      'items': jsonEncode(steps)
    };
  }
}