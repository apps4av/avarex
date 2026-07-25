#!/usr/bin/env python3
"""Generate 6B6 (Minute Man) NMEA for runway awareness testing.

One midfield crossing of RWY 03/21, then takeoff and landing on RWY 03
(3110 × 48 asphalt). Soft-field / short-runway audio is easier to trigger
here than at KBVY; turf 12/30 (1600 ft) is available in the DB if you later
want an even shorter TO/LD.

AvareX consumes 1 fix/sec — step size == ground speed.
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone

# airportrunways rows for 6B6 (main.db)
RWY03 = (42.4566333333333, -71.5205138888889)
RWY21 = (42.4648027777778, -71.5172055555555)
RWY12 = (42.4603638888889, -71.5192055555556)
RWY30 = (42.4591138888889, -71.5135222222222)
MID_0321 = ((RWY03[0] + RWY21[0]) / 2, (RWY03[1] + RWY21[1]) / 2)

FIELD_ALT_M = 82.0  # ~268 ft field elev; Storage.airborne if alt > 100
TAXI_MPS = 3.0
TAXI_KT = 5.8
HOLD_SEC = 8


def bearing(a, b):
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl = math.radians(b[1] - a[1])
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return math.degrees(math.atan2(y, x)) % 360


def offset(p, dist_m, hdg):
    R = 6371000.0
    q = math.radians(hdg)
    lat1, lon1 = math.radians(p[0]), math.radians(p[1])
    lat2 = math.asin(
        math.sin(lat1) * math.cos(dist_m / R)
        + math.cos(lat1) * math.sin(dist_m / R) * math.cos(q)
    )
    lon2 = lon1 + math.atan2(
        math.sin(q) * math.sin(dist_m / R) * math.cos(lat1),
        math.cos(dist_m / R) - math.sin(lat1) * math.sin(lat2),
    )
    return math.degrees(lat2), math.degrees(lon2)


def meters(a, b):
    return math.hypot(
        (b[0] - a[0]) * 111320,
        (b[1] - a[1]) * 111320 * math.cos(math.radians(a[0])),
    )


HDG03 = bearing(RWY03, RWY21)
HDG21 = (HDG03 + 180) % 360
LEFT = (HDG03 - 90) % 360
RIGHT = (HDG03 + 90) % 360

# Hold-short / cross 03/21 from the right (ramp) side toward the left.
HOLD_SHORT = offset(MID_0321, 90, RIGHT)
START = offset(HOLD_SHORT, 150, RIGHT)
AFTER_CROSS = offset(MID_0321, 90, LEFT)
THR03 = offset(RWY03, 60, HDG03)
ROTATE = offset(RWY03, 500, HDG03)
DEPART = offset(RWY21, 600, HDG03)
CROSSWIND = offset(DEPART, 700, LEFT)
DOWNWIND_END = offset(offset(RWY03, 200, HDG21), 700, LEFT)
BASE = offset(DOWNWIND_END, 400, RIGHT)
FINAL_START = offset(RWY03, 1800, HDG21)
FINAL_MID = offset(RWY03, 700, HDG21)

Fix = tuple[float, float, float, float, float]


def lerp(a, b, t):
    return a + (b - a) * t


def segment_ground(a, b, speed_kt, alt_m, step_m=None) -> list[Fix]:
    if step_m is None:
        step_m = max(1.0, speed_kt * 0.514444)
    dist = meters(a, b)
    n = max(2, int(dist / step_m) + 1)
    hdg = bearing(a, b)
    out: list[Fix] = []
    for j in range(n):
        t = j / (n - 1)
        out.append(
            (
                lerp(a[0], b[0], t),
                lerp(a[1], b[1], t),
                alt_m,
                speed_kt,
                hdg,
            )
        )
    return out


def segment_flight(a, b, speed_kt, alt0, alt1, hdg=None) -> list[Fix]:
    step_m = max(1.0, speed_kt * 0.514444)
    dist = meters(a, b)
    n = max(2, int(dist / step_m) + 1)
    if hdg is None:
        hdg = bearing(a, b)
    out: list[Fix] = []
    for j in range(n):
        t = j / (n - 1)
        out.append(
            (
                lerp(a[0], b[0], t),
                lerp(a[1], b[1], t),
                lerp(alt0, alt1, t),
                speed_kt,
                hdg,
            )
        )
    return out


def hold(p, sec, alt_m, hdg) -> list[Fix]:
    return [(p[0], p[1], alt_m, 0.0, hdg)] * sec


def stitch(*parts: list[Fix]) -> list[Fix]:
    out: list[Fix] = []
    for part in parts:
        if not part:
            continue
        if not out:
            out.extend(part)
        else:
            out.extend(part[1:] if part[0][:2] == out[-1][:2] else part)
    return out


def ramp_speed(fixes: list[Fix], spd0: float, spd1: float) -> list[Fix]:
    if len(fixes) < 2:
        return fixes
    out = []
    for i, (lat, lon, alt, _spd, hdg) in enumerate(fixes):
        t = i / (len(fixes) - 1)
        out.append((lat, lon, alt, lerp(spd0, spd1, t), hdg))
    return out


def build_cross_takeoff_landing() -> list[Fix]:
    """Cross 03/21 midfield → taxi to 03 → takeoff → left pattern → land 03."""
    taxi = stitch(
        segment_ground(START, HOLD_SHORT, TAXI_KT, FIELD_ALT_M, TAXI_MPS),
        hold(HOLD_SHORT, 4, FIELD_ALT_M, bearing(HOLD_SHORT, MID_0321)),
        segment_ground(HOLD_SHORT, MID_0321, TAXI_KT, FIELD_ALT_M, TAXI_MPS),
        segment_ground(MID_0321, AFTER_CROSS, TAXI_KT, FIELD_ALT_M, TAXI_MPS),
        segment_ground(AFTER_CROSS, THR03, TAXI_KT, FIELD_ALT_M, TAXI_MPS),
        hold(THR03, HOLD_SEC, FIELD_ALT_M, HDG03),
    )

    roll = ramp_speed(
        segment_ground(THR03, ROTATE, 40.0, FIELD_ALT_M),
        12.0,
        55.0,
    )
    climb1 = segment_flight(ROTATE, DEPART, 70.0, FIELD_ALT_M, 250.0, HDG03)
    climb2 = segment_flight(DEPART, CROSSWIND, 75.0, 250.0, 400.0)
    downwind = segment_flight(CROSSWIND, DOWNWIND_END, 75.0, 400.0, 400.0, HDG21)
    base = segment_flight(DOWNWIND_END, BASE, 70.0, 400.0, 300.0)
    to_final = segment_flight(BASE, FINAL_START, 70.0, 300.0, 250.0, HDG03)
    final_long = segment_flight(FINAL_START, FINAL_MID, 65.0, 250.0, 160.0, HDG03)
    final_short = segment_flight(FINAL_MID, THR03, 60.0, 160.0, 110.0, HDG03)

    flare_pts = []
    for j, alt in enumerate([95.0, 70.0, 50.0, FIELD_ALT_M]):
        p = offset(THR03, 30.0 * j / 3.0, HDG03)
        flare_pts.append((p[0], p[1], alt, 55.0 - 5.0 * j, HDG03))

    after = offset(THR03, 180, HDG03)
    landing_roll = ramp_speed(
        segment_ground(THR03, after, 40.0, FIELD_ALT_M),
        45.0,
        0.0,
    )

    return stitch(
        taxi,
        roll,
        climb1,
        climb2,
        downwind,
        base,
        to_final,
        final_long,
        final_short,
        flare_pts,
        landing_roll,
        hold(after, HOLD_SEC, FIELD_ALT_M, HDG03),
    )


def nmea_lat(lat):
    hemi = "N" if lat >= 0 else "S"
    lat = abs(lat)
    d = int(lat)
    return f"{d:02d}{(lat - d) * 60:06.3f}", hemi


def nmea_lon(lon):
    hemi = "E" if lon >= 0 else "W"
    lon = abs(lon)
    d = int(lon)
    return f"{d:03d}{(lon - d) * 60:06.3f}", hemi


def sentence(body):
    c = 0
    for ch in body:
        c ^= ord(ch)
    return f"${body}*{c:02X}"


GSA = "GPGSA,A,3,01,02,03,04,05,06,07,08,09,10,11,12,1.0,1.0,1.0"


def write_nmea(fixes: list[Fix], filename: str):
    t0 = datetime(2026, 7, 24, 17, 0, 0, tzinfo=timezone.utc)
    lines = []
    for i, (lat, lon, alt, spd, hdg) in enumerate(fixes):
        t = t0 + timedelta(seconds=i)
        ts = t.strftime("%H%M%S.000")
        date = t.strftime("%d%m%y")
        lat_s, ns = nmea_lat(lat)
        lon_s, ew = nmea_lon(lon)
        lines.append(
            sentence(
                f"GPGGA,{ts},{lat_s},{ns},{lon_s},{ew},1,12,1.0,"
                f"{alt:.1f},M,0.0,M,,"
            )
        )
        lines.append(sentence(GSA))
        lines.append(
            sentence(
                f"GPRMC,{ts},A,{lat_s},{ns},{lon_s},{ew},"
                f"{spd:05.1f},{hdg:05.1f},{date},000.0,W"
            )
        )
    with open(filename, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{filename}: {len(fixes)} fixes (~{len(fixes) // 60}m {len(fixes) % 60}s)")


if __name__ == "__main__":
    write_nmea(build_cross_takeoff_landing(), "nmea_6b6_cross_to_ld.txt")
