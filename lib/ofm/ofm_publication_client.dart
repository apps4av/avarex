import 'package:http/http.dart' as http;

import 'ofm_publication.dart';
import 'ofm_region.dart';

class OfmPublicationClient {
  final http.Client _client;
  final Uri baseUri;

  OfmPublicationClient({
    http.Client? client,
    Uri? baseUri,
  })  : _client = client ?? http.Client(),
        baseUri = baseUri ?? Uri.parse('https://snapshots.openflightmaps.org/publicationServices/');

  static String currentAiracCycle() => airacCycleAt(DateTime.now().toUtc());

  static String airacCycleAt(DateTime value) {
    final epoch = DateTime.utc(2015, 11, 12);
    final cycles = value.toUtc().difference(epoch).inDays ~/ 28;
    var year = 15;
    var number = 12;
    for (var index = 0; index < cycles; index++) {
      number++;
      if (number > 13) {
        year++;
        number = 1;
      }
    }
    return '${year.toString().padLeft(2, '0')}${number.toString().padLeft(2, '0')}';
  }

  Uri publicationUri({required String region, required String cycle}) {
    final code = OfmRegions.publicationCode(region);
    return baseUri.resolve('${code}_$cycle.xml');
  }

  Future<OfmPublication> fetch({required String region, required String cycle}) async {
    final uri = publicationUri(region: region, cycle: cycle);
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OfmPublicationException('Unable to fetch OFM publication $uri (${response.statusCode})');
    }
    return OfmPublication.parse(region: region, cycle: cycle, xml: response.body);
  }
}

class OfmPublicationException implements Exception {
  final String message;
  const OfmPublicationException(this.message);

  @override
  String toString() => message;
}
