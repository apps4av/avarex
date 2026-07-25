#!/usr/bin/env python3
"""Offline replica of RunwayAwareness crossing detection.

Reads an NMEA file the same way AvareX does (GGA/RMC), uses real
airportrunways rows from main.db, and reports where a crossing alert
would fire. Used to debug missed runway crossings without running the app.

Usage:
  python3 sim_runway_awareness.py nmea_kbvy_taxi_rwy16.txt KBVY
"""
import math
import sqlite3
import sys

DB = "/Users/zkhan/Library/Containers/com.apps4av.avaremp/Data/Documents/avarex/main.db"

CROSS_TRACK_BUFFER_FT = 75.0
ALIGN_HEADING_DEG = 25.0
CROSSING_LOOKAHEAD_SEC = 15.0
CROSSING_MAX_CROSS_FT = 250.0
CROSSING_ALONG_PAD_FT = 150.0
CROSSING_MIN_SPEED_KT = 3.0
RUNWAY_ROLL_SPEED_KT = 15.0
M_TO_FT = 3.28084


MIN_RUNWAY_END_SEPARATION_M = 100.0


def runway_rows(airport, con=None):
    """Raw airportrunways rows for an airport, as the app reads them."""
    owned = con is None
    con = con or sqlite3.connect(DB)
    try:
        row = con.execute(
            "select DLID from airports where LocationID=?", (airport,)
        ).fetchone()
        if row is None:
            raise SystemExit(f"airport {airport} not found")
        return con.execute(
            "select LEIdent,HEIdent,Length,Width,Surface,LELatitude,LELongitude,"
            "HELatitude,HELongitude,LEHeadingT from airportrunways where DLID=?",
            (row[0],),
        ).fetchall()
    finally:
        if owned:
            con.close()


def load_runways(airport, con=None):
    """Mirrors RunwayAwareness._parseRunways.

    Both ends must have idents and coordinates, and the ends must be at least
    MIN_RUNWAY_END_SEPARATION_M apart. Helipads / stubs are dropped rather than
    falling back to the ARP, which used to draw a phantom centerline through
    the terminal (KORD H1).
    """
    out = []
    for le_id, he_id, length, width, surface, lelat, lelon, helat, helon, lehdg in runway_rows(
        airport, con
    ):
        if not (le_id or "").strip() or not (he_id or "").strip():
            continue
        try:
            le = (float(lelat), float(lelon))
            he = (float(helat), float(helon))
        except (TypeError, ValueError):
            continue
        if meters(le, he) < MIN_RUNWAY_END_SEPARATION_M:
            continue

        try:
            length_ft = float(length)
        except (TypeError, ValueError):
            length_ft = 0.0
        if length_ft <= 0:
            length_ft = meters(le, he) * M_TO_FT

        try:
            width_ft = float(width)
        except (TypeError, ValueError):
            width_ft = 75.0

        try:
            heading = float(lehdg)
        except (TypeError, ValueError):
            heading = bearing(le, he)

        out.append(
            {
                "le_ident": le_id.strip(),
                "he_ident": he_id.strip(),
                "length_ft": length_ft,
                "width_ft": width_ft,
                "le": le,
                "he": he,
                "le_hdg": heading,
                "he_hdg": (heading + 180) % 360,
            }
        )
    return out


def bearing(a, b):
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl = math.radians(b[1] - a[1])
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return math.degrees(math.atan2(y, x)) % 360


def meters(a, b):
    R = 6371000.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp = p2 - p1
    dl = math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))


def signed_angle(deg):
    d = deg % 360
    if d > 180:
        d -= 360
    if d < -180:
        d += 360
    return d


def smallest_angle(a, b):
    d = abs(a - b) % 360
    return 360 - d if d > 180 else d


def runway_frame(p, rw):
    """(along_ft, cross_ft) in the LE->HE frame."""
    len_m = max(1.0, meters(rw["le"], rw["he"]))
    brg = bearing(rw["le"], rw["he"])
    dist_m = meters(rw["le"], p)
    brg_p = bearing(rw["le"], p)
    ang = math.radians(signed_angle(brg_p - brg))
    along_m = dist_m * math.cos(ang)
    cross_m = dist_m * math.sin(ang)
    scale = rw["length_ft"] / (len_m * M_TO_FT)
    return along_m * M_TO_FT * scale, cross_m * M_TO_FT


def imminent_crossing(here, heading, speed_kt, rw):
    """Returns (fires, debug_dict) mirroring _imminentCenterlineCrossing."""
    dbg = {}
    if (
        smallest_angle(heading, rw["le_hdg"]) <= ALIGN_HEADING_DEG
        or smallest_angle(heading, rw["he_hdg"]) <= ALIGN_HEADING_DEG
    ):
        dbg["reject"] = "aligned"
        return False, dbg

    along, cross = runway_frame(here, rw)
    rwy_brg = bearing(rw["le"], rw["he"])
    rel = signed_angle(heading - rwy_brg)
    speed_fps = speed_kt * 1.68781
    cross_rate = speed_fps * math.sin(math.radians(rel))
    along_rate = speed_fps * math.cos(math.radians(rel))
    dbg.update(along=along, cross=cross, rel=rel, cross_rate=cross_rate)

    min_along = -CROSSING_ALONG_PAD_FT
    max_along = rw["length_ft"] + CROSSING_ALONG_PAD_FT

    if abs(cross) <= rw["width_ft"] / 2 + CROSS_TRACK_BUFFER_FT and (
        min_along <= along <= max_along
    ):
        dbg["fire"] = "on_centerline"
        return True, dbg

    if abs(cross) > CROSSING_MAX_CROSS_FT:
        dbg["reject"] = f"cross {abs(cross):.0f}ft > {CROSSING_MAX_CROSS_FT:.0f}ft"
        return False, dbg

    if cross == 0 or cross * cross_rate >= 0:
        dbg["reject"] = "not_closing"
        return False, dbg

    ttl = abs(cross) / abs(cross_rate)
    dbg["ttl"] = ttl
    if ttl > CROSSING_LOOKAHEAD_SEC:
        dbg["reject"] = f"ttl {ttl:.0f}s > {CROSSING_LOOKAHEAD_SEC:.0f}s"
        return False, dbg

    contact = along + along_rate * ttl
    dbg["contact_along"] = contact
    if contact < min_along or contact > max_along:
        dbg["reject"] = "contact off segment"
        return False, dbg
    dbg["fire"] = "imminent"
    return True, dbg


def on_runway_operation(pos, hdg, spd, runways):
    """Mirrors RunwayAwareness._onRunwayOperation (takeoff / landing roll)."""
    if spd < RUNWAY_ROLL_SPEED_KT:
        return False
    for rw in runways:
        along, cross = runway_frame(pos, rw)
        if abs(cross) > rw["width_ft"] / 2 + CROSS_TRACK_BUFFER_FT:
            continue
        if not (
            -CROSS_TRACK_BUFFER_FT <= along <= rw["length_ft"] + CROSS_TRACK_BUFFER_FT
        ):
            continue
        if (
            smallest_angle(hdg, rw["le_hdg"]) <= ALIGN_HEADING_DEG
            or smallest_angle(hdg, rw["he_hdg"]) <= ALIGN_HEADING_DEG
        ):
            return True
    return False


def crossing_runways(pos, hdg, spd, runways):
    """Mirrors RunwayAwareness._crossingRunways: every imminent runway."""
    if spd < CROSSING_MIN_SPEED_KT:
        return []
    if on_runway_operation(pos, hdg, spd, runways):
        return []
    return [rw for rw in runways if imminent_crossing(pos, hdg, spd, rw)[0]]


def parse_nmea(path):
    """Yield (lat, lon, speed_kt, heading) as the app computes them."""
    fixes = []
    gga = None
    with open(path) as f:
        for line in f:
            body = line.strip().split("*")[0]
            tok = body.split(",")
            if body.startswith("$GPGGA") and len(tok) >= 11:
                v = float(tok[2])
                d = int(v) // 100
                lat = (v - d * 100) / 60 + d
                v = float(tok[4])
                d = int(v) // 100
                lon = (v - d * 100) / 60 + d
                if tok[5] == "W":
                    lon = -lon
                gga = (lat, lon)
            elif body.startswith("$GPRMC") and len(tok) >= 9:
                v = float(tok[3])
                d = int(v) // 100
                lat = (v - d * 100) / 60 + d
                v = float(tok[5])
                d = int(v) // 100
                lon = (v - d * 100) / 60 + d
                if tok[6] == "W":
                    lon = -lon
                # app: speed m/s = round(kt * 0.514446) -> int, then *1.94384
                speed_mps = round(float(tok[7]) * 0.514446)
                speed_kt = speed_mps * 1.94384
                heading = round(float(tok[8]))
                pos = gga if gga else (lat, lon)
                fixes.append((pos[0], pos[1], speed_kt, float(heading)))
    return fixes


def main():
    nmea = sys.argv[1] if len(sys.argv) > 1 else "nmea_kbvy_taxi_rwy16.txt"
    airport = sys.argv[2] if len(sys.argv) > 2 else "KBVY"
    runways = load_runways(airport)
    fixes = parse_nmea(nmea)
    print(f"{airport}: {len(runways)} runways, {len(fixes)} fixes from {nmea}")
    for rw in runways:
        print(
            f"  {rw['le_ident']}/{rw['he_ident']} len={rw['length_ft']:.0f}ft "
            f"hdg={rw['le_hdg']:.0f} brg={bearing(rw['le'], rw['he']):.1f}"
        )

    firing = {}
    first_reject = {}
    for i, (lat, lon, spd, hdg) in enumerate(fixes):
        if spd < CROSSING_MIN_SPEED_KT:
            continue
        if on_runway_operation((lat, lon), hdg, spd, runways):
            continue
        for rw in runways:
            name = f"{rw['le_ident']}/{rw['he_ident']}"
            fires, dbg = imminent_crossing((lat, lon), hdg, spd, rw)
            if fires:
                firing.setdefault(name, []).append((i, dbg))
            elif name not in first_reject:
                first_reject[name] = (i, dbg)

    print("\n--- crossing alert windows (fix index == seconds at 1 Hz) ---")
    for name, hits in firing.items():
        idx = [h[0] for h in hits]
        groups = []
        start = prev = idx[0]
        for j in idx[1:]:
            if j - prev > 3:
                groups.append((start, prev))
                start = j
            prev = j
        groups.append((start, prev))
        for lo, hi in groups:
            print(f"{name}: alert from t={lo}s to t={hi}s ({hi - lo + 1}s)")
        d = hits[0][1]
        print(
            f"   first fire: cross={d.get('cross', 0):.0f}ft "
            f"along={d.get('along', 0):.0f}ft ttl={d.get('ttl', 0):.0f}s "
            f"({d.get('fire')})"
        )
    if not firing:
        print("NO CROSSING WOULD FIRE")
        for name, (i, dbg) in first_reject.items():
            print(f"  {name} sample reject @fix{i}: {dbg}")

    print("\n--- speed check ---")
    spds = sorted({f[2] for f in fixes})
    print(f"distinct speed_kt values seen by app: {spds}")


if __name__ == "__main__":
    main()
