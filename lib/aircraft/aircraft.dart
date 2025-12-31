class Aircraft {
  final String tail;
  final String type;
  final String wake;
  final String icao;
  final String equipment;
  final String cruiseTas;
  final String surveillance;
  final String fuelEndurance;
  final String color;
  final String pic;
  final String picInfo;
  final String sinkRate;
  final String fuelBurn;
  final String base;
  final String other;

  Aircraft(
      this.tail,
      this.type,
      this.wake,
      this.icao,
      this.equipment,
      this.cruiseTas,
      this.surveillance,
      this.fuelEndurance,
      this.color,
      this.pic,
      this.picInfo,
      this.sinkRate,
      this.fuelBurn,
      this.base,
      this.other);

  factory Aircraft.empty() {
    return Aircraft(
      "",
      "",
      "LIGHT",
      "",
      "S",
      "",
      "N",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "");
  }

  factory Aircraft.fromMap(Map<String, dynamic> map) {
    return Aircraft(
      (map['tail'] as String).toUpperCase(),
      (map['type'] as String).toUpperCase(),
      (map['wake'] as String).toUpperCase(),
      (map['icao'] as String).toUpperCase(),
      (map['equipment'] as String).toUpperCase(),
      (map['cruiseTas'] as String).toUpperCase(),
      (map['surveillance'] as String).toUpperCase(),
      (map['fuelEndurance'] as String).toUpperCase(),
      (map['color'] as String).toUpperCase(),
      (map['pic'] as String).toUpperCase(),
      (map['picInfo'] as String).toUpperCase(),
      (map['sinkRate'] as String).toUpperCase(),
      (map['fuelBurn'] as String).toUpperCase(),
      (map['base'] as String).toUpperCase(),
      (map['other'] as String).toUpperCase(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tail': tail.toUpperCase(),
      'type': type.toUpperCase(),
      'wake': wake.toUpperCase(),
      'icao': icao.toUpperCase(),
      'equipment': equipment.toUpperCase(),
      'cruiseTas': cruiseTas.toUpperCase(),
      'surveillance': surveillance.toUpperCase(),
      'fuelEndurance': fuelEndurance.toUpperCase(),
      'color': color.toUpperCase(),
      'pic': pic.toUpperCase(),
      'picInfo': picInfo.toUpperCase(),
      'sinkRate': sinkRate.toUpperCase(),
      'fuelBurn': fuelBurn.toUpperCase(),
      'base': base.toUpperCase(),
      'other': other.toUpperCase(),
    };
  }
}