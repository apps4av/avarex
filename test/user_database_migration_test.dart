import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaremp/data/user_database_helper.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('recent migration adds source columns and preserves existing rows', () async {
    final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);
    await database.execute('''
create table recent (
  id integer primary key autoincrement,
  LocationID text,
  FacilityName text,
  Type text,
  ARPLatitude float,
  ARPLongitude float,
  unique(LocationID, Type) on conflict replace
)
''');
    await database.insert('recent', {
      'LocationID': 'KJFK', 'FacilityName': 'JOHN F KENNEDY',
      'Type': 'AIRPORT', 'ARPLatitude': 40.64, 'ARPLongitude': -73.78,
    });

    await UserDatabaseHelper.migrateRecentSourceSchema(database);

    final columns = await database.rawQuery('pragma table_info(recent)');
    expect(columns.map((row) => row['name']), containsAll(['Source', 'SourceRegion', 'SourceCycle']));
    final rows = await database.query('recent');
    expect(rows.single['LocationID'], 'KJFK');
    expect(rows.single['Source'], 'FAA');
    await database.insert('recent', {
      'LocationID': 'ESMS', 'FacilityName': 'MALMO', 'Type': 'AIRPORT',
      'ARPLatitude': 55.53, 'ARPLongitude': 13.37,
      'Source': 'OFM', 'SourceRegion': 'ES', 'SourceCycle': '2609',
    });
  });
}
