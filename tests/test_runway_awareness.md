# Runway crossing awareness tests

`test_runway_awareness.py` checks the crossing detection in
`lib/instruments/runway_awareness.dart` against real runway geometry from
`main.db`, over **every** `Type=AIRPORT` that has at least one usable runway
after the same filtering the app uses (both ends present, ends ≥100 m apart).

It drives `sim_runway_awareness.py`, a Python replica of the Dart detector.
A constants test parses the Dart source directly, so the replica cannot drift
from the app without the suite failing.

## Run

```bash
cd tests
python3 test_runway_awareness.py            # full database
python3 -m unittest test_runway_awareness -v
```

Optional faster smoke run (first N airports by LocationID):

```bash
RWY_TEST_COUNT=100 python3 test_runway_awareness.py
```

## What it covers

| Test | Checks |
|---|---|
| `ConstantsMatchDart` | Replica thresholds equal the Dart `static const` values |
| `AirportSample` | Every usable airport is loaded; runways are well-formed; incomplete rows never kept |
| `KnownDegenerateRunways` | 53AZ / IN16 / MT96 / WT15 sub-100 m rows and KORD `H1` / `10X` are filtered; KORD terminal is silent on all 24 headings |
| `CrossingAnnounced` | Perpendicular taxi over midfield announces each runway exactly once |
| `NoFalseAlerts` | Distant ramp, parallel taxi, aligned takeoff roll, and stopped-at-hold-short all stay silent |

Airports that only have helipads or incomplete stubs are omitted — the app
would have no centerline to watch for those either.

## Verifying the suite has teeth

The tests were mutation-checked by breaking `sim_runway_awareness.py` one
change at a time and confirming a failure:

| Mutation | Result |
|---|---|
| Remove the 100 m end-separation filter | 4 failures |
| `CROSSING_LOOKAHEAD_SEC` 15 → 1 | 1 failure |
| Remove aligned takeoff/landing suppression | 11 failures |
| `CROSSING_MAX_CROSS_FT` 250 → 5000 | 1 failure |

## Limitation

This exercises the Python replica, not the Dart directly, because
`RunwayAwareness` needs `Storage`, the audio player, and the database. The
constants test plus the shared `main.db` geometry keep the two aligned, but a
logic change in Dart still needs the matching change in the replica.
