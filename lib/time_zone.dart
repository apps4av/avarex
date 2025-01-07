
class TimeZone {
  //calculates the timestamp from the passed Zulu time in METAR format (e.g. DDHHMMZ)
  //any trailing values after the Z are disregarded
  //if there isn't 7 characters to create a Zulu time, or letters in first six locations, returns null
  static DateTime? parseZuluTime(String s)
  {
    if(s.length < 7 || int.tryParse(s.substring(0,5)) == null)
    {
      return null;
    }
    DateTime now = DateTime.now().toUtc();
    DateTime expires = DateTime.utc(
        now.year,
        now.month,
        now.day, //day
        0,
        0);
    int from = int.parse(s[2]!);
    int to = int.parse(s[3]!);
    // if from > to then its next day
    expires = expires.add(Duration(days: to < from ? 1 : 0, hours: int.parse(s[3]!.substring(0, 2)), minutes: int.parse(s[5]!.substring(0, 2))));
    return expires;
  }
}
