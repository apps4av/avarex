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

  static String getCutInDate(int year) {
    int first = _getFirstDate(year);
    return "$year-01-$first 09:00";
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

  // this will work till 2026
  static String getCurrentCycle() {
    var now = DateTime.now();
    var formatter = DateFormat('yy');
    int year = int.parse(formatter.format(now));
    DateTime givenDate = DateTime.parse(getCutInDate(2000 + year));
    DateTime currentDate = DateTime.now().toUtc();
    String passed = ((currentDate.difference(givenDate).inDays ~/ 28) + 1).toString().padLeft(2, '0');
    String cycle = "$year$passed";
    return cycle;
  }

}