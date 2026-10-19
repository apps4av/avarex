import 'package:avaremp/link/link_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("LinkMessage", () {
    test("hello round trip", () {
      final LinkMessage message = LinkMessage.hello(
        id: "abc",
        name: "Panel iPad",
        role: LinkRole.master,
      );
      final LinkMessage? parsed = LinkMessage.tryParse(message.encode());
      expect(parsed, isNotNull);
      expect(parsed!.isHello, isTrue);
      expect(parsed.id, "abc");
      expect(parsed.name, "Panel iPad");
      expect(parsed.role, LinkRole.master);
      expect(parsed.summary, "hello  Panel iPad  master");
    });

    test("plan round trip keeps the active waypoint and integer coordinates", () {
      final LinkMessage message = LinkMessage.plan(
        id: "abc",
        name: "Panel iPad",
        role: LinkRole.master,
        planName: "KBOS KACK",
        waypointIndex: 2,
        destinationIndex: 4,
        plan: <Map<String, dynamic>>[
          <String, dynamic>{
            "LocationID": "KBOS",
            "FacilityName": "BOSTON",
            "Type": "AIRPORT",
            "ARPLatitude": 42,
            "ARPLongitude": -71,
          },
          <String, dynamic>{
            "LocationID": "V1",
            "FacilityName": "V1",
            "Type": "AIRWAY",
            "ARPLatitude": 42.5,
            "ARPLongitude": -71.2,
          },
        ],
      );
      final String raw = message.encode();
      final LinkMessage? parsed = LinkMessage.tryParse(raw);
      expect(parsed, isNotNull);
      expect(parsed!.isPlan, isTrue);
      expect(parsed.planName, "KBOS KACK");
      expect(parsed.waypointIndex, 2);
      expect(parsed.destinationIndex, 4);
      expect(parsed.plan.length, 2);
      expect(parsed.plan[0]["ARPLatitude"], 42.0);
      expect(parsed.plan[0]["ARPLatitude"], isA<double>());
      expect(parsed.plan[1]["Type"], "AIRWAY");
      expect(parsed.pointKey, "KBOS|AIRPORT\nV1|AIRWAY");
      expect(parsed.summary, contains("wp 2.4"));
    });

    test("rejects other JSON and other versions", () {
      expect(LinkMessage.tryParse("not json"), isNull);
      expect(LinkMessage.tryParse('{"type":"hello","id":"a"}'), isNull);
      expect(
        LinkMessage.tryParse(
            '{"avarex":2,"type":"hello","id":"a","name":"n","role":"master"}'),
        isNull,
      );
      expect(
        LinkMessage.tryParse(
            '{"avarex":1,"type":"weather","id":"a","name":"n","role":"master"}'),
        isNull,
      );
      expect(
        LinkMessage.tryParse(
            '{"avarex":1,"type":"plan","id":"a","name":"n","role":"master"}'),
        isNull,
      );
    });

    test("unknown role is off and a blank name becomes AvareX", () {
      final LinkMessage? parsed = LinkMessage.tryParse(
          '{"avarex":1,"type":"hello","id":"a","name":"  ","role":"captain"}');
      expect(parsed, isNotNull);
      expect(parsed!.role, LinkRole.off);
      expect(parsed.name, "AvareX");
    });
  });
}
