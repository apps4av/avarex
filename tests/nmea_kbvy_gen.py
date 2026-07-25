#!/usr/bin/env python3
"""Generate KBVY NMEA tracks for runway awareness testing.

AvareX consumes GPS at 1 Hz (`StackWithOne.pop` keeps only the newest fix),
so one fix == one second of intended flight time. Step size is therefore the
ground speed: metres/fix ≈ m/s.

RMC speed must stay ≥ ~3.9 kt for crossings: RMCMessage stores speed as an
int in m/s, so slower values quantize below the 3 kt threshold. Takeoff /
landing intents need ≥ 15 kt and airborne altitude > 100 m (Storage.airborne).

Outputs:
  nmea_kbvy_foxtrot_rwy16.txt   Alpha → Foxtrot → RWY 16 (crossing only)
  nmea_kbvy_taxi_rwy16.txt      full: taxi / cross / Foxtrot / TO / pattern / LD
  nmea_kbvy_to_ld_rwy16.txt     short: hold RWY 16 → takeoff → pattern → land
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone

# airportrunways rows for KBVY (main.db)
RWY16 = (42.5919455833333, -70.9219251388889)
RWY34 = (42.5813369722222, -70.9101480833333)
MID = ((RWY16[0] + RWY34[0]) / 2, (RWY16[1] + RWY34[1]) / 2)

FIELD_ALT_M = 32.0          # ~ field elevation; Storage.airborne if alt > 100
TAXI_MPS = 3.0              # ≈ 5.8 kt
TAXI_KT = 5.8
HOLD_SEC = 10


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


HDG16 = bearing(RWY16, RWY34)
HDG34 = (HDG16 + 180) % 360
ALPHA_SIDE = (HDG16 - 90) % 360
RAMP_SIDE = (HDG16 + 90) % 360


def alpha_at(fraction, lateral_m=95):
    p = (
        RWY16[0] + (RWY34[0] - RWY16[0]) * fraction,
        RWY16[1] + (RWY34[1] - RWY16[1]) * fraction,
    )
    return offset(p, lateral_m, ALPHA_SIDE)


TOWER = offset(offset(MID, 280, RAMP_SIDE), 180, HDG16)
HOLD_SHORT_MID = offset(MID, 80, RAMP_SIDE)
THR16 = offset(RWY16, 80, HDG16)
# Rotate / mid-roll point ~700 m down the runway from threshold.
ROTATE = offset(RWY16, 700, HDG16)
# Climb-out past the far end.
DEPART = offset(RWY34, 800, HDG16)
# Left traffic: crosswind / downwind / base / final for RWY 16.
CROSSWIND = offset(DEPART, 900, ALPHA_SIDE)
DOWNWIND_START = offset(CROSSWIND, 200, HDG34)
DOWNWIND_END = offset(alpha_at(0.0, 900), 400, HDG34)
BASE = offset(DOWNWIND_END, 500, RAMP_SIDE)
# Final start ~1.2 nm on extended centerline.
FINAL_START = offset(RWY16, 2200, HDG34)
FINAL_MID = offset(RWY16, 900, HDG34)


# A fix is (lat, lon, alt_m, speed_kt, heading_deg)
Fix = tuple[float, float, float, float, float]


def lerp(a, b, t):
    return a + (b - a) * t


def segment_ground(a, b, speed_kt, alt_m, step_m=None) -> list[Fix]:
    """Straight taxi/roll between two points at constant speed & altitude."""
    if step_m is None:
        step_m = max(1.0, speed_kt * 0.514444)  # kt → m/s at 1 Hz
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
                0.0 if (j == 0 and speed_kt < 1) else speed_kt,
                hdg,
            )
        )
    return out


def segment_flight(
    a,
    b,
    speed_kt,
    alt0,
    alt1,
    hdg=None,
) -> list[Fix]:
    """Airborne leg; step size matches speed so 1 fix = 1 s."""
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
    """Concatenate segments, dropping duplicate first point of each next part."""
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
    """Override speeds along an existing ground roll (takeoff acceleration)."""
    if len(fixes) < 2:
        return fixes
    out = []
    for i, (lat, lon, alt, _spd, hdg) in enumerate(fixes):
        t = i / (len(fixes) - 1)
        out.append((lat, lon, alt, lerp(spd0, spd1, t), hdg))
    return out


def build_taxi_to_threshold() -> list[Fix]:
    route = [
        TOWER,
        offset(TOWER, 120, bearing(TOWER, HOLD_SHORT_MID)),
        HOLD_SHORT_MID,
        MID,
        alpha_at(0.50),
        alpha_at(0.30),
        alpha_at(0.14),
        alpha_at(0.04),
        THR16,
    ]
    parts = []
    for i in range(len(route) - 1):
        parts.append(
            segment_ground(route[i], route[i + 1], TAXI_KT, FIELD_ALT_M, TAXI_MPS)
        )
    return stitch(*parts) + hold(THR16, HOLD_SEC, FIELD_ALT_M, HDG16)


def build_foxtrot_only() -> list[Fix]:
    route = [alpha_at(0.14), alpha_at(0.04), THR16]
    parts = [
        segment_ground(route[i], route[i + 1], TAXI_KT, FIELD_ALT_M, TAXI_MPS)
        for i in range(len(route) - 1)
    ]
    return stitch(*parts) + hold(THR16, HOLD_SEC, FIELD_ALT_M, HDG16)


def build_takeoff_pattern_landing() -> list[Fix]:
    """Hold on RWY 16 → takeoff roll → climb → left pattern → final → land."""
    # Takeoff roll: accelerate 0 → 55 kt while rolling toward rotate point.
    roll = ramp_speed(
        segment_ground(THR16, ROTATE, 40.0, FIELD_ALT_M),
        12.0,
        55.0,
    )
    # Liftoff / initial climb still runway-aligned (takeoff intent → climb-out).
    climb1 = segment_flight(ROTATE, DEPART, 70.0, FIELD_ALT_M, 250.0, HDG16)
    # Crosswind.
    climb2 = segment_flight(DEPART, CROSSWIND, 75.0, 250.0, 400.0)
    # Downwind (opposite runway heading).
    downwind = segment_flight(CROSSWIND, DOWNWIND_END, 75.0, 400.0, 400.0, HDG34)
    # Base.
    base = segment_flight(DOWNWIND_END, BASE, 70.0, 400.0, 300.0)
    # Turn final — establish RWY 16 heading outside the threshold.
    to_final = segment_flight(BASE, FINAL_START, 70.0, 300.0, 250.0, HDG16)
    # Long final descending; keep alt > 100 m for most of final so
    # Storage.airborne stays true (FlightStatus also stays airborne via speed).
    final_long = segment_flight(FINAL_START, FINAL_MID, 65.0, 250.0, 160.0, HDG16)
    final_short = segment_flight(FINAL_MID, THR16, 60.0, 160.0, 110.0, HDG16)
    # Last seconds: descend through the AGL window toward the threshold.
    flare_pts = []
    for j, alt in enumerate([95.0, 70.0, 50.0, FIELD_ALT_M]):
        p = offset(THR16, 40.0 * j / 3.0, HDG16)
        flare_pts.append((p[0], p[1], alt, 55.0 - 5.0 * j, HDG16))
    after = offset(THR16, 200, HDG16)
    landing_roll = ramp_speed(
        segment_ground(THR16, after, 40.0, FIELD_ALT_M),
        45.0,
        0.0,
    )
    return stitch(
        hold(THR16, HOLD_SEC, FIELD_ALT_M, HDG16),
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
        hold(after, HOLD_SEC, FIELD_ALT_M, HDG16),
    )


def build_full() -> list[Fix]:
    taxi = build_taxi_to_threshold()
    # Drop the leading hold of the TO/LD block — taxi already held at THR16.
    told = build_takeoff_pattern_landing()
    # Skip duplicate hold at start of told (first HOLD_SEC fixes).
    return stitch(taxi, told[HOLD_SEC:])


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
    t0 = datetime(2026, 7, 24, 16, 0, 0, tzinfo=timezone.utc)
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
    write_nmea(build_foxtrot_only(), "nmea_kbvy_foxtrot_rwy16.txt")
    write_nmea(build_takeoff_pattern_landing(), "nmea_kbvy_to_ld_rwy16.txt")
    write_nmea(build_full(), "nmea_kbvy_taxi_rwy16.txt")
