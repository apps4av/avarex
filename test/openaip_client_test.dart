import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:avaremp/openaip/openaip_client.dart';

void main() {
  test('sends API key and follows paginated country results', () async {
    final requests = <http.Request>[];
    final client = OpenAipClient(
      apiKey: 'test-key',
      client: MockClient((request) async {
        requests.add(request);
        final page = request.url.queryParameters['page'];
        return http.Response(jsonEncode({
          'page': int.parse(page!),
          'limit': 2,
          'totalCount': 3,
          'totalPages': 2,
          if (page == '1') 'nextPage': 2,
          'items': page == '1' ? [{'_id': 'a'}, {'_id': 'b'}] : [{'_id': 'c'}],
        }), 200);
      }),
    );

    final items = await client.fetchCountry(OpenAipDataset.obstacles, 'SE', limit: 2);

    expect(items.map((item) => item['_id']), ['a', 'b', 'c']);
    expect(requests, hasLength(2));
    expect(requests.first.headers['x-openaip-api-key'], 'test-key');
    expect(requests.first.url.queryParameters['country'], 'SE');
  });

  test('rejects an empty API key before making a request', () async {
    final client = OpenAipClient(apiKey: '');
    expect(
      () => client.fetchCountry(OpenAipDataset.airports, 'SE'),
      throwsA(isA<OpenAipException>()),
    );
  });

  test('reports authentication failures without exposing the key', () async {
    final client = OpenAipClient(
      apiKey: 'secret-key',
      client: MockClient((_) async => http.Response('{"message":"forbidden"}', 403)),
    );
    await expectLater(
      client.fetchCountry(OpenAipDataset.navaids, 'SE'),
      throwsA(predicate((error) =>
        error is OpenAipException &&
        error.toString().contains('403') &&
        !error.toString().contains('secret-key'))),
    );
  });

  test('uses totalPages when the API omits nextPage', () async {
    final requestedPages = <String>[];
    final client = OpenAipClient(
      apiKey: 'test-key',
      client: MockClient((request) async {
        final page = request.url.queryParameters['page']!;
        requestedPages.add(page);
        return http.Response(jsonEncode({
          'page': int.parse(page),
          'totalPages': 2,
          'items': [{'_id': 'item-$page'}],
        }), 200);
      }),
    );

    final items = await client.fetchCountry(OpenAipDataset.obstacles, 'SE');

    expect(requestedPages, ['1', '2']);
    expect(items, hasLength(2));
  });
}
