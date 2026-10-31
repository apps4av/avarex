import 'dart:math' as math;

/// One WSR-88D radar. Elevation is the antenna base in meters above sea level.
class NexradSite {
  final String id;
  final double lat;
  final double lon;
  final double elevationM;

  const NexradSite(this.id, this.lat, this.lon, this.elevationM);
}

/// Sites ordered by distance from a point, nearest first.
List<({NexradSite site, double distanceNm})> nexradSitesNear(
    double lat, double lon,
    {int count = 2, double maxNm = 230}) {
  final found = <({NexradSite site, double distanceNm})>[];
  for (final site in nexradSites) {
    final d = _distanceNm(lat, lon, site.lat, site.lon);
    if (d <= maxNm) {
      found.add((site: site, distanceNm: d));
    }
  }
  found.sort((a, b) => a.distanceNm.compareTo(b.distanceNm));
  return found.length > count ? found.sublist(0, count) : found;
}

double _distanceNm(double lat1, double lon1, double lat2, double lon2) {
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dp = p2 - p1;
  final dl = (lon2 - lon1) * math.pi / 180;
  final a = math.pow(math.sin(dp / 2), 2) +
      math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * 3440.065 * math.asin(math.min(1.0, math.sqrt(a.toDouble())));
}

/// WSR-88D sites from the NWS radar station list (api.weather.gov/radar/stations).
const List<NexradSite> nexradSites = [
  NexradSite('KABR', 45.45583, -98.41305, 397),
  NexradSite('KABX', 35.14972, -106.82388, 1789),
  NexradSite('KAKQ', 36.98388, -77.00750, 48),
  NexradSite('KAMA', 35.23333, -101.70927, 1104),
  NexradSite('KAMX', 25.61055, -80.41305, 4),
  NexradSite('KAPX', 44.90634, -84.71953, 446),
  NexradSite('KARX', 43.82277, -91.19110, 389),
  NexradSite('KATX', 48.19461, -122.49568, 161),
  NexradSite('KBBX', 39.49611, -121.63165, 53),
  NexradSite('KBGM', 42.19969, -75.98472, 490),
  NexradSite('KBHX', 40.49833, -124.29215, 732),
  NexradSite('KBIS', 46.77083, -100.76027, 505),
  NexradSite('KBLX', 45.85377, -108.60679, 1109),
  NexradSite('KBMX', 33.17194, -86.76972, 197),
  NexradSite('KBOX', 41.95577, -71.13686, 36),
  NexradSite('KBRO', 25.91555, -97.41860, 7),
  NexradSite('KBUF', 42.94860, -78.73694, 211),
  NexradSite('KBYX', 24.59694, -81.70333, 2),
  NexradSite('KCAE', 33.94860, -81.11861, 70),
  NexradSite('KCBW', 46.03916, -67.80642, 227),
  NexradSite('KCBX', 43.49021, -116.23602, 942),
  NexradSite('KCCX', 40.92305, -78.00389, 733),
  NexradSite('KCLE', 41.41305, -81.86000, 233),
  NexradSite('KCLX', 32.65552, -81.04219, 35),
  NexradSite('KCRP', 27.78388, -97.51083, 14),
  NexradSite('KCXX', 44.51110, -73.16639, 97),
  NexradSite('KCYS', 41.15194, -104.80610, 1868),
  NexradSite('KDAX', 38.50111, -121.67782, 9),
  NexradSite('KDDC', 37.76083, -99.96888, 789),
  NexradSite('KDFX', 29.27250, -100.28027, 345),
  NexradSite('KDGX', 32.27999, -89.98444, 151),
  NexradSite('KDIX', 39.94694, -74.41072, 45),
  NexradSite('KDLH', 46.83694, -92.20971, 435),
  NexradSite('KDMX', 41.73110, -93.72285, 299),
  NexradSite('KDOX', 38.82555, -75.44000, 15),
  NexradSite('KDTX', 42.69999, -83.47166, 336),
  NexradSite('KDVN', 41.61166, -90.58083, 230),
  NexradSite('KDYX', 32.53833, -99.25416, 462),
  NexradSite('KEAX', 38.81024, -94.26446, 303),
  NexradSite('KEMX', 31.89361, -110.63027, 1586),
  NexradSite('KENX', 42.58655, -74.06408, 565),
  NexradSite('KEOX', 31.46055, -85.45938, 144),
  NexradSite('KEPZ', 31.87305, -106.69799, 1251),
  NexradSite('KESX', 35.70111, -114.89138, 1483),
  NexradSite('KEVX', 30.56503, -85.92166, 43),
  NexradSite('KEWX', 29.70405, -98.02860, 204),
  NexradSite('KEYX', 35.09777, -117.56074, 846),
  NexradSite('KFCX', 37.02416, -80.27416, 874),
  NexradSite('KFDR', 34.36219, -98.97666, 386),
  NexradSite('KFDX', 34.63416, -103.61888, 1417),
  NexradSite('KFFC', 33.36333, -84.56583, 262),
  NexradSite('KFSD', 43.58777, -96.72888, 436),
  NexradSite('KFSX', 34.57433, -111.19843, 2261),
  NexradSite('KFTG', 39.78663, -104.54580, 1675),
  NexradSite('KFWS', 32.57277, -97.30313, 212),
  NexradSite('KGGW', 48.20635, -106.62468, 702),
  NexradSite('KGJX', 39.06222, -108.21375, 3059),
  NexradSite('KGLD', 39.36694, -101.70027, 1113),
  NexradSite('KGRB', 44.49862, -88.11110, 216),
  NexradSite('KGRK', 30.72166, -97.38277, 164),
  NexradSite('KGRR', 42.89388, -85.54488, 237),
  NexradSite('KGSP', 34.88330, -82.21983, 291),
  NexradSite('KGWX', 33.89691, -88.32919, 155),
  NexradSite('KGYX', 43.89130, -70.25636, 125),
  NexradSite('KHDC', 30.51960, -90.40740, 43),
  NexradSite('KHDX', 33.07699, -106.12002, 1287),
  NexradSite('KHGX', 29.47194, -95.07888, 5),
  NexradSite('KHNX', 36.31416, -119.63213, 74),
  NexradSite('KHPX', 36.73666, -87.28499, 172),
  NexradSite('KHTX', 34.93055, -86.08361, 537),
  NexradSite('KICT', 37.65444, -97.44305, 407),
  NexradSite('KICX', 37.59104, -112.86221, 3244),
  NexradSite('KILN', 39.42027, -83.82166, 322),
  NexradSite('KILX', 40.15049, -89.33679, 188),
  NexradSite('KIND', 39.70749, -86.28027, 241),
  NexradSite('KINX', 36.17499, -95.56413, 204),
  NexradSite('KIWA', 33.28916, -111.66999, 415),
  NexradSite('KIWX', 41.35860, -85.70000, 292),
  NexradSite('KJAX', 30.48463, -81.70190, 19),
  NexradSite('KJGX', 32.67499, -83.35111, 159),
  NexradSite('KJKL', 37.59083, -83.31305, 416),
  NexradSite('KLBB', 33.65413, -101.81416, 1005),
  NexradSite('KLCH', 30.12530, -93.21588, 17),
  NexradSite('KLGX', 47.11689, -124.10663, 77),
  NexradSite('KLNX', 41.95794, -100.57621, 919),
  NexradSite('KLOT', 41.60444, -88.08444, 202),
  NexradSite('KLRX', 40.73972, -116.80277, 2067),
  NexradSite('KLSX', 38.69888, -90.68277, 185),
  NexradSite('KLTX', 33.98916, -78.42916, 20),
  NexradSite('KLVX', 37.97527, -85.94388, 219),
  NexradSite('KLWX', 38.97610, -77.48750, 89),
  NexradSite('KLZK', 34.83638, -92.26194, 173),
  NexradSite('KMAF', 31.94346, -102.18924, 883),
  NexradSite('KMAX', 42.08111, -122.71735, 2290),
  NexradSite('KMBX', 48.39249, -100.86443, 455),
  NexradSite('KMHX', 34.77583, -76.87639, 9),
  NexradSite('KMKX', 42.96777, -88.55055, 292),
  NexradSite('KMLB', 28.11305, -80.65444, 11),
  NexradSite('KMOB', 30.67944, -88.23972, 63),
  NexradSite('KMPX', 44.84888, -93.56552, 301),
  NexradSite('KMQT', 46.53110, -87.54833, 430),
  NexradSite('KMRX', 36.16833, -83.40194, 408),
  NexradSite('KMSX', 47.04110, -113.98610, 2417),
  NexradSite('KMTX', 41.26277, -112.44777, 1975),
  NexradSite('KMUX', 37.15522, -121.89843, 1057),
  NexradSite('KMVX', 47.52805, -97.32499, 301),
  NexradSite('KMXX', 32.53664, -85.78975, 136),
  NexradSite('KNKX', 32.91888, -117.04193, 291),
  NexradSite('KNQA', 35.34472, -89.87333, 103),
  NexradSite('KOAX', 41.32027, -96.36680, 350),
  NexradSite('KOHX', 36.24722, -86.56250, 176),
  NexradSite('KOKX', 40.86552, -72.86392, 26),
  NexradSite('KOTX', 47.68055, -117.62582, 727),
  NexradSite('KPAH', 37.06833, -88.77194, 119),
  NexradSite('KPBZ', 40.53166, -80.21794, 361),
  NexradSite('KPDT', 45.69055, -118.85290, 462),
  NexradSite('KPOE', 31.15527, -92.97583, 124),
  NexradSite('KPUX', 38.45944, -104.18138, 1615),
  NexradSite('KRAX', 35.66527, -78.49000, 106),
  NexradSite('KRGX', 39.75405, -119.46202, 2530),
  NexradSite('KRIW', 43.06610, -108.47729, 1697),
  NexradSite('KRLX', 38.31110, -81.72277, 335),
  NexradSite('KRTX', 45.71499, -122.96499, 492),
  NexradSite('KSFX', 43.10559, -112.68612, 1364),
  NexradSite('KSGF', 37.23527, -93.40027, 390),
  NexradSite('KSHV', 32.45083, -93.84124, 83),
  NexradSite('KSJT', 31.37111, -100.49221, 576),
  NexradSite('KSOX', 33.81773, -117.63599, 927),
  NexradSite('KSRX', 35.29041, -94.36188, 200),
  NexradSite('KTBW', 27.70527, -82.40194, 12),
  NexradSite('KTFX', 47.45972, -111.38527, 1140),
  NexradSite('KTLH', 30.39749, -84.32889, 19),
  NexradSite('KTLX', 35.33305, -97.27775, 370),
  NexradSite('KTWX', 38.99694, -96.23249, 417),
  NexradSite('KTYX', 43.75582, -75.68000, 563),
  NexradSite('KUDX', 44.12471, -102.82999, 939),
  NexradSite('KUEX', 40.32083, -98.44194, 602),
  NexradSite('KVAX', 30.89027, -83.00180, 66),
  NexradSite('KVBX', 34.83855, -120.39790, 383),
  NexradSite('KVNX', 36.74083, -98.12749, 369),
  NexradSite('KVTX', 34.41166, -119.17860, 831),
  NexradSite('KVWX', 38.26024, -87.72452, 156),
  NexradSite('KYUX', 32.49527, -114.65668, 53),
  NexradSite('PABC', 60.79194, -161.87637, 49),
  NexradSite('PACG', 56.85277, -135.52915, 63),
  NexradSite('PAEC', 64.51139, -165.29498, 18),
  NexradSite('PAHG', 60.72591, -151.35144, 74),
  NexradSite('PAIH', 59.46194, -146.30109, 20),
  NexradSite('PAKC', 58.67944, -156.62942, 19),
  NexradSite('PAPD', 65.03511, -147.50140, 790),
  NexradSite('PGUA', 13.45583, 144.81112, 83),
  NexradSite('PHKI', 21.89389, -159.55249, 69),
  NexradSite('PHKM', 20.12527, -155.77776, 1174),
  NexradSite('PHMO', 21.13277, -157.18026, 415),
  NexradSite('PHWA', 19.09500, -155.56887, 421),
  NexradSite('RKJK', 35.92417, 126.62222, 24),
  NexradSite('RKSG', 37.20757, 127.28556, 439),
  NexradSite('RODN', 26.30194, 127.90972, 91),
  NexradSite('TJUA', 18.11566, -66.07817, 867),
];
