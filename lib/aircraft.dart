class Aircraft {
  final String tail;
  final String type;
  final String wake;
  final int icao;
  final String equipment;
  final double cruiseTas;
  final String surveillance;
  final double fuelEndurance;
  final String color;
  final String pic;
  final String picInfo;
  final double sinkRate;
  final double fuelBurn;
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

  factory Aircraft.fromMap(Map<String, dynamic> map) {
    return Aircraft(
      map['tail'] as String,
      map['type'] as String,
      map['wake'] as String,
      map['icao'] as int,
      map['equipment'] as String,
      map['cruiseTas'] as double,
      map['surveillance'] as String,
      map['fuelEndurance'] as double,
      map['color'] as String,
      map['pic'] as String,
      map['picInfo'] as String,
      map['sinkRate'] as double,
      map['fuelBurn'] as double,
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