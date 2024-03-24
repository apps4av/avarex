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
      this.base);

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
      "");
  }

  factory Aircraft.fromMap(Map<String, dynamic> map) {
    return Aircraft(
      map['tail'] as String,
      map['type'] as String,
      map['wake'] as String,
      map['icao'] as String,
      map['equipment'] as String,
      map['cruiseTas'] as String,
      map['surveillance'] as String,
      map['fuelEndurance'] as String,
      map['color'] as String,
      map['pic'] as String,
      map['picInfo'] as String,
      map['sinkRate'] as String,
      map['fuelBurn'] as String,
      map['base'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tail': tail,
      'type': type,
      'wake': wake,
      'icao': icao,
      'equipment': equipment,
      'cruiseTas': cruiseTas,
      'surveillance': surveillance,
      'fuelEndurance': fuelEndurance,
      'color': color,
      'pic': pic,
      'picInfo': picInfo,
      'sinkRate': sinkRate,
      'fuelBurn': fuelBurn,
      'base': base,
    };
  }
}