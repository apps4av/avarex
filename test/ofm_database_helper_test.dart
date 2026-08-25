import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofm_schema.dart';

void main() {
  test('OFM schema creates separate ofm.db tables and never main.db tables', () {
    expect(OfmSchema.databaseName, 'ofm.db');
    expect(OfmSchema.createStatements.join('\n'), contains('create table if not exists ofm_region_install'));
    expect(OfmSchema.createStatements.join('\n'), contains('create table if not exists ofm_metadata'));
    expect(OfmSchema.createStatements.join('\n'), contains('create table if not exists ofm_airport'));
    expect(OfmSchema.createStatements.join('\n'), contains('create table if not exists ofm_airport_comm'));
    expect(OfmSchema.createStatements.join('\n'), contains('create table if not exists ofm_runway'));
    expect(OfmSchema.createStatements.join('\n'), contains('create table if not exists ofm_runway_end'));
    expect(OfmSchema.createStatements.join('\n'), contains('create table if not exists ofm_airspace'));
    expect(OfmSchema.createStatements.join('\n'), contains('create table if not exists ofm_waypoint'));
    expect(OfmSchema.createStatements.join('\n'), contains('create table if not exists ofm_airspace_vertex'));
    expect(OfmSchema.createStatements.join('\n'), isNot(contains('create table airports')));
    expect(OfmSchema.createStatements.join('\n'), isNot(contains('main.db')));
  });
}
