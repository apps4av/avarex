import 'dart:typed_data';

import 'package:avaremp/link/link_protocol.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
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

    test("detections round trip keeps boxes, tiers, fov and horizon", () {
      final LinkMessage message = LinkMessage.detections(
        id: "cam",
        name: "Pilot phone",
        role: LinkRole.off,
        detections: const DetectionFrame(
          seq: 812,
          timestampMs: 1790000000000,
          fovH: 65,
          fovV: 37,
          horizonLeft: 0.52,
          horizonRight: 0.58,
          boxes: <DetectionBox>[
            DetectionBox(
              id: 3,
              x: 0.41,
              y: 0.2,
              w: 0.02,
              h: 0.021,
              confidence: 0.62,
              tier: DetectionTier.airplane,
            ),
            DetectionBox(
              id: 4,
              x: 0.7,
              y: 0.3,
              w: 0.01,
              h: 0.01,
              confidence: 0.3,
              tier: DetectionTier.possible,
            ),
          ],
        ),
      );
      expect(message.isVisual, isTrue);
      final LinkMessage? parsed = LinkMessage.tryParse(message.encode());
      expect(parsed, isNotNull);
      expect(parsed!.isDetections, isTrue);
      expect(parsed.role, LinkRole.off);
      final DetectionFrame frame = parsed.detections!;
      expect(frame.seq, 812);
      expect(frame.fovH, 65);
      expect(frame.horizonLeft, 0.52);
      expect(frame.horizonRight, 0.58);
      expect(frame.boxes.length, 2);
      expect(frame.boxes[0].id, 3);
      expect(frame.boxes[0].tier, DetectionTier.airplane);
      expect(frame.boxes[1].tier, DetectionTier.possible);
      expect(frame.airplaneCount, 1);
      expect(parsed.summary, "detections  Pilot phone  2 boxes");
    });

    test("detections with a bad box are rejected", () {
      expect(
        LinkMessage.tryParse(
            '{"avarex":1,"type":"detections","id":"a","name":"n","role":"off",'
            '"seq":1,"ts":2,"boxes":[{"id":1,"x":"left"}]}'),
        isNull,
      );
      expect(
        LinkMessage.tryParse(
            '{"avarex":1,"type":"detections","id":"a","name":"n","role":"off"}'),
        isNull,
      );
    });

    test("preview round trip keeps the jpeg bytes", () {
      final Uint8List jpeg = Uint8List.fromList(
          List<int>.generate(300, (int i) => (i * 7) % 256));
      final LinkMessage message = LinkMessage.preview(
        id: "cam",
        name: "Pilot phone",
        role: LinkRole.off,
        seq: 9,
        width: 240,
        height: 135,
        jpeg: jpeg,
      );
      final LinkMessage? parsed = LinkMessage.tryParse(message.encode());
      expect(parsed, isNotNull);
      expect(parsed!.isPreview, isTrue);
      expect(parsed.previewSeq, 9);
      expect(parsed.previewWidth, 240);
      expect(parsed.previewHeight, 135);
      expect(parsed.preview, jpeg);
    });

    test("preview without a picture or with bad base64 is rejected", () {
      expect(
        LinkMessage.tryParse(
            '{"avarex":1,"type":"preview","id":"a","name":"n","role":"off","seq":1}'),
        isNull,
      );
      expect(
        LinkMessage.tryParse(
            '{"avarex":1,"type":"preview","id":"a","name":"n","role":"off","jpg":"***"}'),
        isNull,
      );
    });

    test("watch round trip names the camera device", () {
      final LinkMessage message = LinkMessage.watch(
        id: "viewer",
        name: "iPad",
        role: LinkRole.slave,
        target: "cam",
      );
      final LinkMessage? parsed = LinkMessage.tryParse(message.encode());
      expect(parsed, isNotNull);
      expect(parsed!.isWatch, isTrue);
      expect(parsed.target, "cam");
      expect(
        LinkMessage.tryParse(
            '{"avarex":1,"type":"watch","id":"a","name":"n","role":"off"}'),
        isNull,
      );
    });

    test("visual messages are not plan or hello messages", () {
      final LinkMessage hello =
          LinkMessage.hello(id: "a", name: "n", role: LinkRole.master);
      expect(hello.isVisual, isFalse);
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
