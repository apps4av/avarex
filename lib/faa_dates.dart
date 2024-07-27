import 'package:intl/intl.dart';

// FAA date stuff
class FaaDates {

  static int _getFirstDate(int year) {
    // Date for first cycle every year in January starting 2014
    switch(year) {
      case 2020:
        return 2;
      case 2021:
        return 28;
      case 2022:
        return 27;
      case 2023:
        return 26;
      case 2024:
        return 25;
      case 2025:
        return 23;
      case 2026:
        return 22;
      case 2027:
        return 21;
      case 2028:
        return 20;
      case 2029:
        return 18;
      default:
        return 0;
    }
  }

  // based on cycle get start and end times
  static String getVersionRange(String cycleName) {
    int cycle;
    try {
      cycle = int.parse(cycleName);
    } catch (e) {
      return "";
    }

    int cycleUpper = (cycle ~/ 100);
    int cycleLower = cycle - (cycleUpper * 100);
    int firstDate = _getFirstDate(2000 + cycleUpper);
    if (firstDate < 1) {
      return "";
    }
    DateFormat sdf = DateFormat("MM/dd/yyyy", "en_US");
    DateTime epoch = DateTime.utc(2000 + cycleUpper, DateTime.january, firstDate, 9, 0, 0);
    epoch = epoch.add(Duration(days: 28 * (cycleLower - 1)));
    String fmt1 = sdf.format(epoch);
    epoch = epoch.add(const Duration(days: 28));
    String fmt2 = sdf.format(epoch);
    return "($fmt1-$fmt2)";
  }

  // this will work till 2029
  static String getCurrentCycle({DateTime? from}) {
    final DateTime epoch = DateTime.parse("2024-01-25 09:00:00Z");
    const int validYears = 5;
    int lastYear = epoch.year % 2000;
    int cycle = 0;
    DateTime now = DateTime.now().toUtc();
    if(from != null) {
      now = from;
    }

    // x years worth
    for(int day = 0; day < validYears * 365; day += 28) {
      DateTime date = epoch.add(Duration(days: day));
      int year = (date.year % 2000);
      if(lastYear == year) {
        cycle++;
      }
      else {
        cycle = 1;
        lastYear = year;
      }
      String faaCycle = "$year${cycle.toString().padLeft(2, '0')}";
      Duration diff = now.difference(date);
      if(diff.inSeconds > 0 && diff.inSeconds < const Duration(days:28).inSeconds) {
        return faaCycle;
      }
    }
    return ("0000");
  }

  static String getNextCycle(String cycle) {
    String range = getVersionRange(cycle);
    RegExp exp = RegExp(r"\((?<start>.*)-(.*)\)");
    RegExpMatch? m = exp.firstMatch(range);
    if(m != null) {
      String? start = m.namedGroup("start");
      if (start != null) {
        // parse date in format MM/dd/yyyy
        DateTime startDt = DateFormat("MM/dd/yyyy").parse(start);
        startDt = startDt.add(const Duration(days: 29));
        return getCurrentCycle(from: startDt);
      }
    }
    return "0000";
  }

}