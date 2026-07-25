#!/usr/bin/env python3
"""Runway crossing awareness tests over every airport in main.db.

Exercises the crossing detection in `sim_runway_awareness.py`, which mirrors
`lib/instruments/runway_awareness.dart`. A constants test parses the Dart
source directly so the replica cannot silently drift from the app.

For each airport with at least one usable runway, synthetic 1 Hz taxi tracks
are built from the real `airportrunways` geometry and run through the detector:

  positive  perpendicular taxi across each runway must announce exactly once
  negative  parked on a ramp far from pavement must stay silent
  negative  taxi parallel alongside a runway must stay silent
  negative  aligned takeoff roll on the runway must stay silent

Run:
  python3 -m unittest test_runway_awareness -v
  python3 test_runway_awareness.py                 # same, with a summary

Optional subset for a faster smoke run (count is a limit, not a sample):
  RWY_TEST_COUNT=100 python3 test_runway_awareness.py
"""
from __future__ import annotations

import math
import os
import re
import sqlite3
import unittest
from pathlib import Path

import sim_runway_awareness as sim

# Default: every Type=AIRPORT with usable runway geometry. RWY_TEST_COUNT
# caps how many are loaded (ordered by LocationID) for a quicker local smoke.
_LIMIT = os.environ.get("RWY_TEST_COUNT")
AIRPORT_LIMIT = int(_LIMIT) if _LIMIT else None

DART_SOURCE = (
    Path(__file__).resolve().parents[1] / "lib" / "instruments" / "runway_awareness.dart"
)

EARTH_RADIUS_M = 6371000.0


def offset(point, distance_m, heading_deg):
    """Point at distance/heading from another point (great circle)."""
    course = math.radians(heading_deg)
    lat1, lon1 = math.radians(point[0]), math.radians(point[1])
    ratio = distance_m / EARTH_RADIUS_M
    lat2 = math.asin(
        math.sin(lat1) * math.cos(ratio)
        + math.cos(lat1) * math.sin(ratio) * math.cos(course)
    )
    lon2 = lon1 + math.atan2(
        math.sin(course) * math.sin(ratio) * math.cos(lat1),
        math.cos(ratio) - math.sin(lat1) * math.sin(lat2),
    )
    return math.degrees(lat2), math.degrees(lon2)


def midpoint(rw):
    return ((rw["le"][0] + rw["he"][0]) / 2, (rw["le"][1] + rw["he"][1]) / 2)


def straight_track(start, end, speed_kt, step_m=3.0):
    """1 Hz fixes along a straight ground path: (lat, lon, speed_kt, heading)."""
    heading = sim.bearing(start, end)
    total = sim.meters(start, end)
    count = max(2, int(total / step_m) + 1)
    fixes = []
    for i in range(count):
        fraction = i / (count - 1)
        fixes.append(
            (
                start[0] + (end[0] - start[0]) * fraction,
                start[1] + (end[1] - start[1]) * fraction,
                speed_kt,
                heading,
            )
        )
    return fixes


def announcements(fixes, runways):
    """Replays a track and returns announced runway keys in order.

    Mirrors the once-until-clear latching in RunwayAwareness.update: a runway
    announces once and re-arms only after it stops being an imminent crossing.
    """
    announced = set()
    order = []
    for lat, lon, speed_kt, heading in fixes:
        crossings = sim.crossing_runways((lat, lon), heading, speed_kt, runways)
        active = {f"{rw['le_ident']}/{rw['he_ident']}" for rw in crossings}
        announced &= active
        for key in sorted(active - announced):
            announced.add(key)
            order.append(key)
    return order


def load_all_airports(limit=None):
    """Every Type=AIRPORT that has at least one usable runway after filtering.

    Airports with only helipads / incomplete stubs are omitted — same as the
    app, which would have no centerline to watch. Order is LocationID so a
    failure always points at the same airport.
    """
    con = sqlite3.connect(sim.DB)
    try:
        ids = [
            row[0]
            for row in con.execute(
                "select LocationID from airports where Type='AIRPORT' "
                "order by LocationID"
            )
        ]
        picked = []
        for airport in ids:
            runways = sim.load_runways(airport, con)
            if runways:
                picked.append((airport, runways))
            if limit is not None and len(picked) >= limit:
                break
        return picked
    finally:
        con.close()


def count_airports_with_usable_runways():
    """How many Type=AIRPORT rows have at least one runway after filtering."""
    con = sqlite3.connect(sim.DB)
    try:
        n = 0
        for (airport,) in con.execute(
            "select LocationID from airports where Type='AIRPORT'"
        ):
            if sim.load_runways(airport, con):
                n += 1
        return n
    finally:
        con.close()


AIRPORTS = load_all_airports(AIRPORT_LIMIT)


class ConstantsMatchDart(unittest.TestCase):
    """The replica must use the same thresholds as the app."""

    def dart_constant(self, name):
        source = DART_SOURCE.read_text()
        match = re.search(rf"double {name} = ([0-9.]+);", source)
        self.assertIsNotNone(match, f"{name} not found in {DART_SOURCE.name}")
        return float(match.group(1))

    def test_thresholds_match(self):
        for dart_name, sim_value in [
            ("_crossTrackBufferFt", sim.CROSS_TRACK_BUFFER_FT),
            ("_alignHeadingDeg", sim.ALIGN_HEADING_DEG),
            ("_crossingLookaheadSec", sim.CROSSING_LOOKAHEAD_SEC),
            ("_crossingMaxCrossFt", sim.CROSSING_MAX_CROSS_FT),
            ("_crossingAlongPadFt", sim.CROSSING_ALONG_PAD_FT),
            ("_crossingMinSpeedKt", sim.CROSSING_MIN_SPEED_KT),
            ("_runwayRollSpeedKt", sim.RUNWAY_ROLL_SPEED_KT),
        ]:
            with self.subTest(constant=dart_name):
                self.assertEqual(self.dart_constant(dart_name), sim_value)

    def test_end_separation_matches(self):
        source = DART_SOURCE.read_text()
        self.assertIn(
            f"_metersBetween(le, he) < {int(sim.MIN_RUNWAY_END_SEPARATION_M)}",
            source,
            "Dart runway-end separation check changed",
        )


class AirportSample(unittest.TestCase):
    def test_covers_every_usable_airport(self):
        self.assertGreater(len(AIRPORTS), 1000, "expected thousands of airports")
        if AIRPORT_LIMIT is not None:
            self.assertEqual(len(AIRPORTS), AIRPORT_LIMIT)
        else:
            self.assertEqual(
                len(AIRPORTS),
                count_airports_with_usable_runways(),
                "airport list does not match the usable set in main.db",
            )

    def test_runways_are_well_formed(self):
        for airport, runways in AIRPORTS:
            for rw in runways:
                with self.subTest(airport=airport, runway=rw["le_ident"]):
                    self.assertTrue(rw["le_ident"], "missing LE ident")
                    self.assertTrue(rw["he_ident"], "missing HE ident")
                    self.assertGreaterEqual(
                        sim.meters(rw["le"], rw["he"]),
                        sim.MIN_RUNWAY_END_SEPARATION_M,
                        "runway ends too close (helipad / stub not filtered)",
                    )
                    self.assertGreater(rw["width_ft"], 0)

    def test_no_phantom_runways_from_incomplete_rows(self):
        """Rows lacking an end must be dropped, never snapped to the ARP."""
        con = sqlite3.connect(sim.DB)
        try:
            checked = 0
            for airport, runways in AIRPORTS:
                kept = {(rw["le_ident"], rw["he_ident"]) for rw in runways}
                for row in sim.runway_rows(airport, con):
                    le_id, he_id = (row[0] or "").strip(), (row[1] or "").strip()
                    try:
                        float(row[7])
                        float(row[8])
                        has_he_coords = True
                    except (TypeError, ValueError):
                        has_he_coords = False
                    if he_id and has_he_coords:
                        continue
                    checked += 1
                    self.assertNotIn(
                        (le_id, he_id),
                        kept,
                        f"{airport}: incomplete runway {le_id}/{he_id} was kept",
                    )
            self.assertGreater(checked, 0, "sample had no incomplete rows to verify")
        finally:
            con.close()


class KnownDegenerateRunways(unittest.TestCase):
    """Pinned regressions for incomplete / stub runway rows.

    These airports are the only ones in main.db whose runway rows survive the
    ident/coordinate checks but have ends closer than the 100 m minimum, plus
    KORD's H1 helipad, which is what produced the phantom centerline through
    the terminal.
    """

    # airport -> runway ident that must be filtered out
    SHORT_SEPARATION = {
        "53AZ": "01",
        "IN16": "18",
        "MT96": "08",
        "WT15": "15",
    }

    def test_short_separation_runways_dropped(self):
        con = sqlite3.connect(sim.DB)
        try:
            for airport, ident in self.SHORT_SEPARATION.items():
                with self.subTest(airport=airport):
                    raw = [
                        (r[0] or "").strip() for r in sim.runway_rows(airport, con)
                    ]
                    self.assertIn(
                        ident, raw, f"{airport} {ident} missing from main.db"
                    )
                    kept = [rw["le_ident"] for rw in sim.load_runways(airport, con)]
                    self.assertNotIn(
                        ident,
                        kept,
                        f"{airport}: runway {ident} has ends <100 m apart "
                        "but was not filtered",
                    )
        finally:
            con.close()

    def test_kord_helipad_dropped(self):
        con = sqlite3.connect(sim.DB)
        try:
            runways = sim.load_runways("KORD", con)
            idents = {rw["le_ident"] for rw in runways}
            self.assertNotIn("H1", idents, "KORD helipad H1 must be filtered")
            self.assertNotIn("10X", idents, "KORD stub 10X must be filtered")
            # The eight real parallel/diagonal runways survive.
            self.assertEqual(len(runways), 8)
        finally:
            con.close()

    def test_kord_terminal_is_silent(self):
        """The ramp position that used to trigger the phantom H1 centerline."""
        con = sqlite3.connect(sim.DB)
        try:
            runways = sim.load_runways("KORD", con)
        finally:
            con.close()
        terminal = (41.9786, -87.9059)
        for heading in range(0, 360, 15):
            with self.subTest(heading=heading):
                fired = sim.crossing_runways(terminal, float(heading), 8.0, runways)
                self.assertEqual(
                    [f"{rw['le_ident']}/{rw['he_ident']}" for rw in fired],
                    [],
                    f"false alert at KORD terminal on heading {heading}",
                )


class CrossingAnnounced(unittest.TestCase):
    """A perpendicular taxi over midfield must announce that runway once."""

    def test_perpendicular_crossing_announces_once(self):
        for airport, runways in AIRPORTS:
            for rw in runways:
                key = f"{rw['le_ident']}/{rw['he_ident']}"
                with self.subTest(airport=airport, runway=key):
                    mid = midpoint(rw)
                    across = (rw["le_hdg"] + 90) % 360
                    start = offset(mid, 120, (across + 180) % 360)
                    end = offset(mid, 120, across)
                    fired = announcements(
                        straight_track(start, end, speed_kt=6.0), runways
                    )
                    self.assertIn(
                        key,
                        fired,
                        f"{airport} {key}: crossing never announced",
                    )
                    self.assertEqual(
                        fired.count(key),
                        1,
                        f"{airport} {key}: announced {fired.count(key)} times",
                    )


class NoFalseAlerts(unittest.TestCase):
    def test_parked_far_from_pavement_is_silent(self):
        """A ramp half a mile off every runway must never announce."""
        for airport, runways in AIRPORTS:
            with self.subTest(airport=airport):
                longest = max(runways, key=lambda rw: rw["length_ft"])
                mid = midpoint(longest)
                across = (longest["le_hdg"] + 90) % 360
                # 0.5 nm abeam midfield, taxiing parallel to the runway.
                ramp = offset(mid, 926, across)
                far_end = offset(ramp, 150, longest["le_hdg"])
                fired = announcements(
                    straight_track(ramp, far_end, speed_kt=8.0), runways
                )
                # Other runways may genuinely pass near the ramp point; only
                # assert the runway we measured from stays quiet.
                key = f"{longest['le_ident']}/{longest['he_ident']}"
                self.assertNotIn(
                    key, fired, f"{airport}: false alert {key} from a distant ramp"
                )

    def test_parallel_taxi_alongside_is_silent(self):
        """A taxiway parallel to the runway is not a crossing."""
        for airport, runways in AIRPORTS:
            for rw in runways:
                key = f"{rw['le_ident']}/{rw['he_ident']}"
                with self.subTest(airport=airport, runway=key):
                    mid = midpoint(rw)
                    across = (rw["le_hdg"] + 90) % 360
                    # Parallel taxiway ~120 ft off the centerline.
                    start = offset(offset(mid, 37, across), 100, rw["he_hdg"])
                    end = offset(offset(mid, 37, across), 100, rw["le_hdg"])
                    fired = announcements(
                        straight_track(start, end, speed_kt=8.0), runways
                    )
                    self.assertNotIn(
                        key,
                        fired,
                        f"{airport} {key}: parallel taxi announced a crossing",
                    )

    def test_aligned_takeoff_roll_is_silent(self):
        """Rolling aligned on the runway is a takeoff, not a crossing."""
        for airport, runways in AIRPORTS:
            for rw in runways:
                key = f"{rw['le_ident']}/{rw['he_ident']}"
                with self.subTest(airport=airport, runway=key):
                    roll_end = offset(
                        rw["le"],
                        min(600.0, sim.meters(rw["le"], rw["he"]) * 0.5),
                        rw["le_hdg"],
                    )
                    fired = announcements(
                        straight_track(rw["le"], roll_end, speed_kt=40.0, step_m=20.0),
                        runways,
                    )
                    self.assertEqual(
                        fired,
                        [],
                        f"{airport} {key}: takeoff roll announced {fired}",
                    )

    def test_below_minimum_speed_is_silent(self):
        """Stopped at the hold-short line must not announce."""
        for airport, runways in AIRPORTS:
            for rw in runways:
                key = f"{rw['le_ident']}/{rw['he_ident']}"
                with self.subTest(airport=airport, runway=key):
                    mid = midpoint(rw)
                    across = (rw["le_hdg"] + 90) % 360
                    hold_short = offset(mid, 60, (across + 180) % 360)
                    fixes = [(hold_short[0], hold_short[1], 0.0, across)] * 10
                    self.assertEqual(announcements(fixes, runways), [])


if __name__ == "__main__":
    total_runways = sum(len(rw) for _, rw in AIRPORTS)
    scope = (
        f"limit={AIRPORT_LIMIT}"
        if AIRPORT_LIMIT is not None
        else "all airports with usable runways"
    )
    print(
        f"{scope}  airports={len(AIRPORTS)}  runways={total_runways}\n"
        f"first: {', '.join(a for a, _ in AIRPORTS[:10])} ...\n"
    )
    unittest.main(verbosity=2)
