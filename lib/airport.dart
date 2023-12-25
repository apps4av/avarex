import 'package:avaremp/destination.dart';

class Airport {

  static String parseFrequencies(AirportDestination airport) {

    List<Map<String, dynamic>> frequencies = airport.frequencies;

    List<String> atis = [];
    List<String> clearance = [];
    List<String> ground = [];
    List<String> tower = [];

    for(Map<String, dynamic> f in frequencies) {
      // Type, Freq
      String type = f['Type'];
      String freq = f['Freq'];
      if(type == 'LCL/P') {
        tower.add(freq);
      }
      else if(type == 'GND/P') {
        ground.add(freq);
      }
      else if(type.contains('ATIS')) {
        atis.add(freq);
      }
      else if(type == 'CD/P' || type.contains('CLNC')) {
        clearance.add(freq);
      }
      else {
        continue;
      }
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