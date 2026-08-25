class OfmSchema {
  OfmSchema._();

  static const String databaseName = 'ofm.db';
  static const int version = 3;

  static const List<String> createStatements = [
    '''
create table if not exists ofm_metadata (
  key text primary key,
  value text not null
)
''',
    '''
create table if not exists ofm_region_install (
  region text not null,
  cycle text not null,
  effective text,
  expiration text,
  publication_url text,
  ofmx_url text,
  mbtiles_url text,
  mbtiles_path text,
  installed_at text not null,
  primary key(region, cycle)
)
''',
    '''
create table if not exists ofm_airport (
  id text primary key, region text not null, cycle text not null,
  code_id text not null, icao text, iata text, gps_code text,
  name text, city text, type text, lat real not null, lon real not null,
  elevation_ft real, mag_var real, transition_alt_ft real,
  source text not null default 'OFM', raw_mid text
)
''',
    'create index if not exists idx_ofm_airport_code on ofm_airport(code_id)',
    'create index if not exists idx_ofm_airport_lat_lon on ofm_airport(lat, lon)',
    '''
create table if not exists ofm_airport_comm (
  id text primary key, airport_id text not null, code_type text,
  value text, remark text, sequence integer,
  foreign key(airport_id) references ofm_airport(id) on delete cascade
)
''',
    '''
create table if not exists ofm_runway (
  id text primary key, airport_id text not null, designation text,
  length_m real, width_m real, surface text, condition text, remark text,
  foreign key(airport_id) references ofm_airport(id) on delete cascade
)
''',
    '''
create table if not exists ofm_runway_end (
  id text primary key, runway_id text not null, designation text,
  lat real, lon real, true_bearing real, mag_bearing real, tdze_ft real,
  pattern text, vasi_type text, remark text,
  foreign key(runway_id) references ofm_runway(id) on delete cascade
)
''',
    '''
create table if not exists ofm_waypoint (
  id text primary key, region text not null, cycle text not null, raw_mid text,
  code_id text not null, kind text not null, type text, name text,
  lat real not null, lon real not null, frequency text, mag_var real,
  airport_code text, remark text
)
''',
    'create index if not exists idx_ofm_waypoint_code on ofm_waypoint(code_id)',
    'create index if not exists idx_ofm_waypoint_lat_lon on ofm_waypoint(lat, lon)',
    '''
create table if not exists ofm_airspace (
  id text primary key, region text not null, cycle text not null,
  code_id text, code_type text, class text, name text,
  alt_upper_code text, alt_upper_value real, alt_upper_uom text, alt_upper_ft real,
  alt_lower_code text, alt_lower_value real, alt_lower_uom text, alt_lower_ft real,
  selectable text, remark text, raw_mid text
)
''',
    '''
create table if not exists ofm_airspace_vertex (
  airspace_id text not null, sequence integer not null, code_type text,
  lat real not null, lon real not null, arc_lat real, arc_lon real, datum text,
  primary key(airspace_id, sequence),
  foreign key(airspace_id) references ofm_airspace(id) on delete cascade
)
''',
    'create index if not exists idx_ofm_airspace_vertex_lat_lon on ofm_airspace_vertex(lat, lon)',
  ];
}
