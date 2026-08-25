import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:avaremp/ofm/ofm_publication_client.dart';

void main() {
  test('uses the OFM FIR publication code for Sweden', () {
    final client = OfmPublicationClient();
    expect(
      client.publicationUri(region: 'ES', cycle: '2601').toString(),
      'https://snapshots.openflightmaps.org/publicationServices/ESAA_2601.xml',
    );
  });

  test('fetch parses a publication from the mapped endpoint', () async {
    late Uri requested;
    final client = OfmPublicationClient(client: MockClient((request) async {
      requested = request.url;
      return http.Response('<publications><nearCycles><cycle id="2601" string="current" /></nearCycles></publications>', 200);
    }));

    final publication = await client.fetch(region: 'ES', cycle: '2601');
    expect(requested.path, endsWith('/ESAA_2601.xml'));
    expect(publication.region, 'ES');
  });

  test('non-success status produces a typed publication exception', () async {
    final client = OfmPublicationClient(client: MockClient((_) async => http.Response('missing', 404)));
    expect(() => client.fetch(region: 'ES', cycle: '2601'), throwsA(isA<OfmPublicationException>()));
  });

  test('calculates current AIRAC cycle without a hard-coded year', () {
    expect(OfmPublicationClient.airacCycleAt(DateTime.utc(2026, 8, 20)), '2609');
    expect(OfmPublicationClient.airacCycleAt(DateTime.utc(2026, 9, 3)), '2610');
  });
}
