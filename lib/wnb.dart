import 'dart:convert';
import 'dart:ui';

class Wnb {
  String name;
  String aircraft;
  List<String> items;
  double minX;
  double minY;
  double maxX;
  double maxY;
  List<String> points;

  Wnb(this.name, this.aircraft, this.items, this.minX, this.minY, this.maxX, this.maxY, this.points);

  static List<Offset> getPoints(List<String> points) {
    List<Offset> result = [];
    for (String point in points) {
      List<String> parts = point.split(',');
      result.add(Offset(double.parse(parts[0]), double.parse(parts[1])));
    }
    return result;
  }

  static List<String> getPointsAsString(List<Offset> points) {
    List<String> result = [];
    for (Offset point in points) {
      result.add('${point.dx},${point.dy}');
    }
    return result;
  }

  factory Wnb.empty() {
    return Wnb('New', '', [], 30, 1500, 50, 3000, []);
  }

}


class WeightAndBalanceItem {
  final String description;
  final double weight;
  final double arm;

  WeightAndBalanceItem(this.description, this.weight, this.arm);

  String toJson() {
    Map<String, dynamic> map = {
      'description': description,
      'weight': weight,
      'arm': arm
    };
    return jsonEncode(map);
  }

  factory WeightAndBalanceItem.fromJson(String json) {
    final Map<String, dynamic> map = jsonDecode(json);
    return WeightAndBalanceItem(map['description'] as String, map['weight'] as double, map['arm'] as double);
  }

}

