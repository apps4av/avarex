import 'package:avaremp/plan/plan_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("approach profile altitudes match fixes on the procedure", () {
    final Map<int, int> altitudes = PlanRoute.profileAltitudesForFixes(
      ["BOS", "RW04R", "NERNY"],
      [
        (fix: "bos", altitudeFt: 2000),
        (fix: "RW04R", altitudeFt: 180),
        (fix: "HOLD", altitudeFt: 3000),
        (fix: "NERNY", altitudeFt: null),
      ],
    );
    expect(altitudes[0], 2000);
    expect(altitudes[1], 180);
    expect(altitudes.containsKey(2), isFalse);
  });
}
