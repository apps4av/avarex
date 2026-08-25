class OfmRegion {
  final String code;
  final String publicationCode;
  final String name;
  final bool enabled;

  const OfmRegion({
    required this.code,
    required this.publicationCode,
    required this.name,
    this.enabled = true,
  });
}

class OfmRegions {
  OfmRegions._();

  static const List<OfmRegion> all = [
    OfmRegion(code: 'ED', publicationCode: 'ED', name: 'Germany'),
    OfmRegion(code: 'EB', publicationCode: 'EBBU', name: 'Belgium'),
    OfmRegion(code: 'EF', publicationCode: 'EFIN', name: 'Finland'),
    OfmRegion(code: 'EH', publicationCode: 'EHAA', name: 'Netherlands'),
    OfmRegion(code: 'EK', publicationCode: 'EKDK', name: 'Denmark'),
    OfmRegion(code: 'EP', publicationCode: 'EPWW', name: 'Poland'),
    OfmRegion(code: 'ES', publicationCode: 'ESAA', name: 'Sweden'),
    OfmRegion(code: 'FA', publicationCode: 'FA', name: 'South Africa'),
    OfmRegion(code: 'FY', publicationCode: 'FYWH', name: 'Namibia'),
    OfmRegion(code: 'LF', publicationCode: 'LF', name: 'France'),
    OfmRegion(code: 'LI', publicationCode: 'LI', name: 'Italy'),
    OfmRegion(code: 'LO', publicationCode: 'LOVV', name: 'Austria'),
    OfmRegion(code: 'LS', publicationCode: 'LSAS', name: 'Switzerland'),
    OfmRegion(code: 'LZ', publicationCode: 'LZBB', name: 'Slovakia'),
  ];

  static OfmRegion byCode(String code) {
    final normalized = code.trim().toUpperCase();
    return all.firstWhere(
      (region) => region.code == normalized || region.publicationCode == normalized,
      orElse: () => OfmRegion(code: normalized, publicationCode: normalized, name: normalized),
    );
  }

  static String publicationCode(String code) => byCode(code).publicationCode;
}
