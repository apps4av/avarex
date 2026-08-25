import 'dart:convert';

import 'package:http/http.dart' as http;

enum OpenAipDataset {
  airports('airports'),
  airspaces('airspaces'),
  navaids('navaids'),
  obstacles('obstacles'),
  reportingPoints('reporting-points');

  final String path;
  const OpenAipDataset(this.path);
}

class OpenAipException implements Exception {
  final String message;
  const OpenAipException(this.message);

  @override
  String toString() => 'OpenAipException: $message';
}

class OpenAipClient {
  final String apiKey;
  final http.Client _client;
  final Uri baseUri;

  OpenAipClient({
    required this.apiKey,
    http.Client? client,
    Uri? baseUri,
  })  : _client = client ?? http.Client(),
        baseUri = baseUri ?? Uri.parse('https://api.core.openaip.net/api/');

  factory OpenAipClient.withKey(String value) => OpenAipClient(apiKey: value);

  Future<List<Map<String, dynamic>>> fetchCountry(
    OpenAipDataset dataset,
    String country, {
    int limit = 1000,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) throw const OpenAipException('An openAIP API key is required.');
    final result = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final uri = baseUri.resolve(dataset.path).replace(queryParameters: {
        'country': country.trim().toUpperCase(),
        'page': '$page',
        'limit': '$limit',
      });
      final response = await _client.get(uri, headers: {
        'x-openaip-api-key': key,
        'Accept': 'application/json',
        'User-Agent': 'AvareX/openAIP',
      });
      if (response.statusCode != 200) {
        throw OpenAipException('Request failed with HTTP ${response.statusCode}. Check the API key and try again.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const OpenAipException('Invalid response from openAIP.');
      }
      final items = decoded['items'];
      if (items is List) {
        result.addAll(items.whereType<Map>().map((item) => Map<String, dynamic>.from(item)));
      }
      final nextPage = decoded['nextPage'];
      if (nextPage is num) {
        page = nextPage.toInt();
        continue;
      }
      final totalPages = decoded['totalPages'];
      if (totalPages is num && page < totalPages.toInt()) {
        page++;
        continue;
      }
      break;
    }
    return result;
  }

  void close() => _client.close();
}
