import 'package:avaremp/app_log.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/logbook/entry.dart';

class Totals {
  double totalFlightTime = 0.0;
  double pilotInCommand = 0.0;
  double dualReceived = 0.0;
  double soloTime = 0.0;
  double crossCountryTime = 0.0;
  double dayTime = 0.0;
  double nightTime = 0.0;
  double actualInstruments = 0.0;
  double simulatedInstruments = 0.0;
  int dayLandings = 0;
  int nightLandings = 0;
  int instrumentApproaches = 0;
  double groundTime = 0.0;
  double flightSimulator = 0.0;

  bool get hasData {
    return totalFlightTime > 0.0 ||
        pilotInCommand > 0.0 ||
        dualReceived > 0.0 ||
        soloTime > 0.0 ||
        crossCountryTime > 0.0 ||
        dayTime > 0.0 ||
        nightTime > 0.0 ||
        actualInstruments > 0.0 ||
        simulatedInstruments > 0.0 ||
        dayLandings > 0 ||
        nightLandings > 0 ||
        instrumentApproaches > 0;
  }

  static Future<Totals> getTotals() async {
    try {
      final List<Entry> entries = await UserDatabaseHelper.db.getAllLogbook();
      final totals = Totals();
      for (final e in entries) {
        totals.totalFlightTime += e.totalFlightTime;
        totals.pilotInCommand += e.pilotInCommand;
        totals.dualReceived += e.dualReceived;
        totals.soloTime += e.soloTime;
        totals.crossCountryTime += e.crossCountryTime;
        totals.dayTime += e.dayTime;
        totals.nightTime += e.nightTime;
        totals.actualInstruments += e.actualInstruments;
        totals.simulatedInstruments += e.simulatedInstruments;
        totals.dayLandings += e.dayLandings;
        totals.nightLandings += e.nightLandings;
        totals.instrumentApproaches += e.instrumentApproaches;
        totals.groundTime += e.groundTime;
        totals.flightSimulator += e.flightSimulator;
      }
      return totals;
    } catch (e) {
      AppLog.logMessage('Error calculating logbook totals: $e');
    }
    return Totals();
  }

}
