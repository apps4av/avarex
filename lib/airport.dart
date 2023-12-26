import 'package:avaremp/destination.dart';

class Airport {

  static String parseFrequencies(AirportDestination airport) {

    List<Map<String, dynamic>> frequencies = airport.frequencies;
    List<Map<String, dynamic>> awos = airport.awos;

    List<String> atis = [];
    List<String> clearance = [];
    List<String> ground = [];
    List<String> tower = [];
    List<String> automated = [];

    for(Map<String, dynamic> f in frequencies) {
      try {
        // Type, Freq
        String type = f['Type'];
        String freq = f['Freq'];
        if (type == 'LCL/P') {
          tower.add(freq);
        }
        else if (type == 'GND/P') {
          ground.add(freq);
        }
        else if (type.contains('ATIS')) {
          atis.add(freq);
        }
        else if (type == 'CD/P' || type.contains('CLNC')) {
          clearance.add(freq);
        }
        else {
          continue;
        }
      }
      catch(e) {}
    }

    for(Map<String, dynamic> f in awos) {
      try {
        // Type, Freq
        automated.add("${f['Type']} ${f['Frequency1']} ${f['Telephone1']}");
        print(f);
      }
      catch(e) {}
    }

    String ret = "";
    if(tower.isNotEmpty) {
      ret += "Tower\n    ";
      ret += tower.join("\n    ");
    }
    if(ground.isNotEmpty) {
      ret += "\nGround\n    ";
      ret += ground.join("\n    ");
    }
    if(clearance.isNotEmpty) {
      ret += "\nClearance\n    ";
      ret += clearance.join("\n    ");
    }
    if(atis.isNotEmpty) {
      ret += "\nATIS\n    ";
      ret += atis.join("\n    ");
    }
    if(airport.ctaf.isNotEmpty) {
      ret += "\nCTAF\n    ";
      ret += airport.ctaf;
    }
    if(airport.unicom.isNotEmpty) {
      ret += "\nUNICOM\n    ";
      ret += airport.unicom;
    }
    if(automated.isNotEmpty) {
      ret += "\nAutomated\n    ";
      ret += automated.join("\n    ");
    }

    return ret;
  }

  static String parseRunways(AirportDestination airport) {

    List<Map<String, dynamic>> runways = airport.runways;

    for(Map<String, dynamic> r in runways) {
//      String type = r['Type'];
    }

    return "";
  }

}