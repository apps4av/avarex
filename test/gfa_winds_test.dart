import 'dart:convert';
import 'dart:typed_data';

import 'package:avaremp/weather/gfa_winds.dart';
import 'package:flutter_test/flutter_test.dart';

/// A GFA wind reply for a 3 x 3 lattice 2 degrees apart from 40N 80W, every point the same.
Uint8List _reply(int dir, int speed) {
  final List<Map<String, dynamic>> features = [
    for (int i = 0; i < 3; i++)
      for (int j = 0; j < 3; j++)
        {
          "geometry": {"coordinates": [-80.0 + 2 * j, 40.0 + 2 * i]},
          "properties": {"wdir": dir, "wspd": speed},
        },
  ];
  return Uint8List.fromList(utf8.encode(jsonEncode({"type": "FeatureCollection", "features": features})));
}

void main() {
  test("encodeWind", () {
    expect(GfaWinds.encodeWind(20, 0), "2720"); // blowing east: from the west
    expect(GfaWinds.encodeWind(-20, 0), "0920");
    expect(GfaWinds.encodeWind(1, 1), "9900");
    expect(GfaWinds.encodeWind(0, -105), "8605"); // from the north at 105 knots
  });

  test("build reads the lattice at each station", () {
    final Uint8List? bytes = GfaWinds.build(
      6,
      "20261105_23_F06",
      List.generate(10, (int l) => _reply(270, 20)),
      [("INS", 41.0, -79.0), ("OUT", 60.0, -79.0)],
    );
    expect(bytes, isNotNull);
    expect(GfaWinds.isGfa(bytes!), isTrue);
    final Map<String, dynamic> json = jsonDecode(utf8.decode(bytes));
    expect(json["fore"], 6);
    expect(json["run"], "20261105_23_F06");
    final Map<String, dynamic> stations = json["s"];
    expect(stations.containsKey("OUT"), isFalse);
    expect(stations["INS"], List.filled(9, "2720"));
  });

  test("build is null without any wind", () {
    expect(GfaWinds.build(6, "x", List.filled(10, null), [("INS", 41.0, -79.0)]), isNull);
  });

  test("isGfa tells GFA data from FD text", () {
    expect(GfaWinds.isGfa(Uint8List.fromList(utf8.encode("FBUS31 KWNO"))), isFalse);
    expect(GfaWinds.isGfa(Uint8List.fromList(utf8.encode('{"gfa":0,"fore":6}'))), isTrue);
  });
}
