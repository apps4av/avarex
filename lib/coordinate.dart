class Coordinate {
  Longitude longitude;
  Latitude latitude;
  Coordinate(this.longitude, this.latitude);

  @override
  String toString() {
    return "${longitude.toString()},${latitude.toString()}";
  }
}

class Latitude {
  double value;
  Latitude(this.value);

  @override
  String toString() {
    return value.toStringAsFixed(4);
  }

}

class Longitude {
  double value;
  Longitude(this.value);

  @override
  String toString() {
    return value.toStringAsFixed(4);
  }
}

