const double _metersToFeet = 3.280839895013123;

double parseOfmCoordinate(String value) {
  final parsed = parseOfmCoordinateOrNull(value);
  if (parsed == null) {
    throw FormatException('Invalid OFMX coordinate', value);
  }
  return parsed;
}

double? parseOfmCoordinateOrNull(String? value) {
  final normalized = value?.trim().toUpperCase() ?? '';
  if (normalized.length < 2) {
    return null;
  }
  final hemisphere = normalized.substring(normalized.length - 1);
  if (!const {'N', 'S', 'E', 'W'}.contains(hemisphere)) {
    return null;
  }
  final number = double.tryParse(normalized.substring(0, normalized.length - 1));
  if (number == null || !number.isFinite || number < 0) {
    return null;
  }
  final latitude = hemisphere == 'N' || hemisphere == 'S';
  if ((latitude && number > 90) || (!latitude && number > 180)) {
    return null;
  }
  return hemisphere == 'S' || hemisphere == 'W' ? -number : number;
}

double? ofmAltitudeFeet(num? value, String? unit) {
  if (value == null) {
    return null;
  }
  switch ((unit ?? '').trim().toUpperCase()) {
    case 'FL':
      return value.toDouble() * 100;
    case 'M':
      return value.toDouble() * _metersToFeet;
    case 'FT':
    case 'F':
    case '':
      return value.toDouble();
    default:
      return null;
  }
}

double? ofmLengthFeet(num? value, String? unit) => ofmAltitudeFeet(value, unit);
