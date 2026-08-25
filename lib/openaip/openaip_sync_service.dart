import 'openaip_client.dart';
import 'openaip_database.dart';

class OpenAipSyncResult {
  final int airports;
  final int navaids;
  final int reportingPoints;
  final int airspaces;
  final int obstacles;

  const OpenAipSyncResult({
    required this.airports,
    required this.navaids,
    required this.reportingPoints,
    required this.airspaces,
    required this.obstacles,
  });
}

class OpenAipSyncService {
  final OpenAipClient client;
  final OpenAipDatabase database;

  const OpenAipSyncService({required this.client, required this.database});

  static OpenAipSyncService create({
    required OpenAipClient client,
    required OpenAipDatabase database,
  }) => OpenAipSyncService(client: client, database: database);

  Future<OpenAipSyncResult> syncCountry(
    String country, {
    void Function(double progress, String message)? onProgress,
  }) async {
    final datasets = <OpenAipDataset>[
      OpenAipDataset.airports,
      OpenAipDataset.navaids,
      OpenAipDataset.reportingPoints,
      OpenAipDataset.airspaces,
      OpenAipDataset.obstacles,
    ];
    final values = <OpenAipDataset, List<Map<String, dynamic>>>{};
    for (var index = 0; index < datasets.length; index++) {
      final dataset = datasets[index];
      onProgress?.call(index / datasets.length, 'Downloading ${dataset.path}...');
      values[dataset] = await client.fetchCountry(dataset, country);
    }
    onProgress?.call(0.95, 'Importing openAIP data...');
    await database.replaceCountry(
      country: country,
      airports: values[OpenAipDataset.airports]!,
      navaids: values[OpenAipDataset.navaids]!,
      reportingPoints: values[OpenAipDataset.reportingPoints]!,
      airspaces: values[OpenAipDataset.airspaces]!,
      obstacles: values[OpenAipDataset.obstacles]!,
    );
    onProgress?.call(1, 'Installed openAIP data.');
    return OpenAipSyncResult(
      airports: values[OpenAipDataset.airports]!.length,
      navaids: values[OpenAipDataset.navaids]!.length,
      reportingPoints: values[OpenAipDataset.reportingPoints]!.length,
      airspaces: values[OpenAipDataset.airspaces]!.length,
      obstacles: values[OpenAipDataset.obstacles]!.length,
    );
  }
}
