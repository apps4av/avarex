// Deep links to aip.aero, a free index that points to each country's official
// national Aeronautical Information Publication (AIP) and approach charts.
//
// aip.aero does not license or host aeronautical data itself; it links straight
// to the latest official AIP of the respective country (DFS, NATS, ENAIRE,
// skeyes, ...). We only build a URL here (Tier 1 hand-off) and let the platform
// browser open it. No data is fetched, cached, or redistributed by the app.
//
// URL scheme (verified empirically against the live site):
//   https://aip.aero/{slug}/vfr/?{ICAO}     -> airport detail page (~48 countries)
//   https://aip.aero/{slug}/                -> country landing page (search)
//   https://aip.aero/                       -> global search (last resort)
//
// A small number of countries (currently France and Belgium/Luxembourg) do not
// expose the guessable "vfr" category slug, so for those we fall back to the
// country landing page, which always resolves.

class AipAero {
  AipAero._();

  static const String baseUrl = 'https://aip.aero';

  // Maps an aip.aero country to its site slug and whether the "vfr" airport
  // deep link is supported. `deepLink == false` means we can only link to the
  // country landing page (the airport detail slug is not guessable).
  static const Map<String, ({String slug, bool deepLink})> _countries = {
    'albania': (slug: 'al', deepLink: true),
    'armenia': (slug: 'am', deepLink: true),
    'australia': (slug: 'au', deepLink: true),
    'austria': (slug: 'at', deepLink: true),
    'azerbaijan': (slug: 'az', deepLink: true),
    'belarus': (slug: 'by', deepLink: true),
    'belgium': (slug: 'be', deepLink: false),
    'bosnia': (slug: 'ba', deepLink: true),
    'bulgaria': (slug: 'bg', deepLink: true),
    'croatia': (slug: 'hr', deepLink: true),
    'cyprus': (slug: 'cy', deepLink: true),
    'czechia': (slug: 'cz', deepLink: true),
    'denmark': (slug: 'dk', deepLink: true),
    'estonia': (slug: 'ee', deepLink: true),
    'finland': (slug: 'fi', deepLink: true),
    'france': (slug: 'fr', deepLink: false),
    'georgia': (slug: 'ge', deepLink: true),
    'germany': (slug: 'de', deepLink: true),
    'greece': (slug: 'gr', deepLink: true),
    'hungary': (slug: 'hu', deepLink: true),
    'iceland': (slug: 'is', deepLink: true),
    'ireland': (slug: 'ie', deepLink: true),
    'italy': (slug: 'it', deepLink: true),
    'kazakhstan': (slug: 'kz', deepLink: true),
    'kosovo': (slug: 'xk', deepLink: true),
    'kyrgyzstan': (slug: 'kg', deepLink: true),
    'latvia': (slug: 'lv', deepLink: true),
    'lithuania': (slug: 'lt', deepLink: true),
    'malta': (slug: 'mt', deepLink: true),
    'moldova': (slug: 'md', deepLink: true),
    'netherlands': (slug: 'nl', deepLink: true),
    'newzealand': (slug: 'nz', deepLink: true),
    'macedonia': (slug: 'mk', deepLink: true),
    'norway': (slug: 'no', deepLink: true),
    'poland': (slug: 'pl', deepLink: true),
    'portugal': (slug: 'pt', deepLink: true),
    'romania': (slug: 'ro', deepLink: true),
    'russia': (slug: 'ru', deepLink: true),
    'serbia': (slug: 'rs', deepLink: true),
    'slovakia': (slug: 'sk', deepLink: true),
    'slovenia': (slug: 'si', deepLink: true),
    'spain': (slug: 'es', deepLink: true),
    'sweden': (slug: 'se', deepLink: true),
    'switzerland': (slug: 'ch', deepLink: true),
    'tajikistan': (slug: 'tj', deepLink: true),
    'turkey': (slug: 'tr', deepLink: true),
    'turkmenistan': (slug: 'tm', deepLink: true),
    'ukraine': (slug: 'ua', deepLink: true),
    'uk': (slug: 'uk', deepLink: true),
    'uzbekistan': (slug: 'uz', deepLink: true),
  };

  // Resolves an ICAO location identifier to an aip.aero country key.
  //
  // ICAO area assignments are prefix-based. We try the most specific match
  // first (3-letter blocks that are shared between neighbouring states, e.g.
  // the UT* block spanning Turkmenistan / Tajikistan / Uzbekistan), then the
  // common 2-letter block, then single-letter (Australia), and finally a broad
  // ex-USSR "U" fallback to Russia.
  static String? _countryKey(String icao) {
    final id = icao.trim().toUpperCase();
    if (id.length < 3) {
      return null;
    }

    // Shared UT* block must be disambiguated by the third letter.
    if (id.startsWith('UT')) {
      switch (id[2]) {
        case 'A': // UTAx
          return 'turkmenistan';
        case 'D': // UTDx
        case 'O': // UTOx
          return 'tajikistan';
        default: // UTN/UTS/UTK/UTT...
          return 'uzbekistan';
      }
    }

    const twoLetter = <String, String>{
      'ED': 'germany', 'ET': 'germany',
      'LO': 'austria',
      'EB': 'belgium', 'EL': 'belgium', // Luxembourg indexed with Belgium
      'LQ': 'bosnia', 'LK': 'czechia', 'EK': 'denmark', 'EE': 'estonia',
      'EF': 'finland', 'LF': 'france', 'UG': 'georgia', 'LG': 'greece',
      'LH': 'hungary', 'BI': 'iceland', 'EI': 'ireland', 'LI': 'italy',
      'EV': 'latvia', 'EY': 'lithuania', 'LM': 'malta', 'LU': 'moldova',
      'EH': 'netherlands', 'NZ': 'newzealand', 'LW': 'macedonia',
      'EN': 'norway', 'EP': 'poland', 'LP': 'portugal', 'LR': 'romania',
      'LY': 'serbia', 'LZ': 'slovakia', 'LJ': 'slovenia',
      'LE': 'spain', 'GC': 'spain', // GC = Canary Islands
      'ES': 'sweden', 'LS': 'switzerland', 'LT': 'turkey',
      'EG': 'uk', 'LA': 'albania', 'UD': 'armenia', 'UB': 'azerbaijan',
      'UM': 'belarus', 'LB': 'bulgaria', 'LC': 'cyprus', 'BK': 'kosovo',
      'UC': 'kyrgyzstan', 'UK': 'ukraine', 'UA': 'kazakhstan',
      'LD': 'croatia',
    };
    final two = id.substring(0, 2);
    final byTwo = twoLetter[two];
    if (byTwo != null) {
      return byTwo;
    }

    // Australia: all Y****.
    if (id.startsWith('Y')) {
      return 'australia';
    }

    // Broad ex-USSR fallback: remaining U-block identifiers are Russia.
    if (id.startsWith('U')) {
      return 'russia';
    }

    return null;
  }

  // True when we can point the user to an aip.aero page for this airport.
  static bool hasChartsFor(String icao) => _countryKey(icao) != null;

  // Builds the best available aip.aero URL for the given ICAO identifier.
  //
  // Returns an airport deep link where supported, otherwise the country
  // landing page, otherwise the global search homepage. Never returns null so
  // the link is always actionable.
  static String urlForAirport(String icao) {
    final id = icao.trim().toUpperCase();
    final key = _countryKey(id);
    if (key == null) {
      return '$baseUrl/';
    }
    final country = _countries[key];
    if (country == null) {
      return '$baseUrl/';
    }
    if (country.deepLink && id.isNotEmpty) {
      return '$baseUrl/${country.slug}/vfr/?$id';
    }
    return '$baseUrl/${country.slug}/';
  }
}
