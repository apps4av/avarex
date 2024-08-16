import 'package:avaremp/geo_calculations.dart';
import 'package:latlong2/latlong.dart';

class Passage {

  double? _lastDistance;
  double? _currentDistance;
  final LatLng _nextDestinationCoordinates;

  Passage(this._nextDestinationCoordinates);

  static const double _passageDistanceMin = 2; // must pass within this nm distance to pass


  // call this on every GPS update
  bool update(LatLng currentCoordinates) {

    GeoCalculations geo = GeoCalculations();

    if (_lastDistance == null) {
      _lastDistance = geo.calculateDistance(currentCoordinates, _nextDestinationCoordinates);
       //Init on first input on location
      return false;
    }

    _currentDistance = geo.calculateDistance(currentCoordinates, _nextDestinationCoordinates);

    bool ret;

    if (_currentDistance! > _lastDistance!) {
      // We are in passage zone, when exit, we have passed
      if (_currentDistance! < _passageDistanceMin) {
        ret = true;
      }
      else {
        ret = false;
      }
    }
    else {
      ret = false;
    }

    _lastDistance = _currentDistance;
    return ret;
  }
}
