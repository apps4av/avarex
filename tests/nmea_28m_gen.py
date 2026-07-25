#!/usr/bin/env python3
"""Generate a 28M crossing → takeoff → landing runway-awareness test.

Uses Cranland's database geometry for RWY 18/36 (1760 x 60 ft asphalt).
AvareX consumes one GPS fix per second, so each segment's metres per fix
matches its reported speed.
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone

RWY18 = (42.0274646666667, -70.8389822777778)
RWY36 = (42.0228164722222, -70.8372183055556)
MID = ((RWY18[0] + RWY36[0]) / 2, (RWY18[1] + RWY36[1]) / 2)

FIELD_ALT_M = 22.0  # 71 ft
TAXI_KT = 5.8
TAXI_STEP_M = 3.0
HOLD_SEC = 8

Fix = tuple[float, float, float, float, float]


def bearing(a, b):
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl = math.radians(b[1] - a[1])
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return math.degrees(math.atan2(y, x)) % 360


def offset(p, distance_m, heading):
    radius = 6371000.0
    course = math.radians(heading)
    lat1, lon1 = math.radians(p[0]), math.radians(p[1])
    lat2 = math.asin(
        math.sin(lat1) * math.cos(distance_m / radius)
        + math.cos(lat1) * math.sin(distance_m / radius) * math.cos(course)
    )
    lon2 = lon1 + math.atan2(
        math.sin(course) * math.sin(distance_m / radius) * math.cos(lat1),
        math.cos(distance_m / radius) - math.sin(lat1) * math.sin(lat2),
    )
    return math.degrees(lat2), math.degrees(lon2)


def meters(a, b):
    return math.hypot(
        (b[0] - a[0]) * 111320,
        (b[1] - a[1]) * 111320 * math.cos(math.radians(a[0])),
    )


def lerp(a, b, fraction):
    return a + (b - a) * fraction


HDG18 = bearing(RWY18, RWY36)
HDG36 = (HDG18 + 180) % 360
LEFT = (HDG18 - 90) % 360
RIGHT = (HDG18 + 90) % 360

# Cross midfield from west to east, taxi north parallel to the runway,
# then enter the RWY 18 threshold.
START = offset(MID, 180, RIGHT)
HOLD_SHORT = offset(MID, 85, RIGHT)
AFTER_CROSS = offset(MID, 85, LEFT)
PARALLEL_18 = offset(RWY18, 85, LEFT)
THR18 = offset(RWY18, 45, HDG18)

ROTATE = offset(RWY18, 350, HDG18)
DEPART = offset(RWY36, 500, HDG18)
CROSSWIND = offset(DEPART, 600, LEFT)
DOWNWIND_END = offset(offset(RWY18, 150, HDG36), 600, LEFT)
BASE = offset(DOWNWIND_END, 350, RIGHT)
FINAL_START = offset(RWY18, 1500, HDG36)
FINAL_MID = offset(RWY18, 550, HDG36)


def segment(a, b, speed_kt, altitude0, altitude1=None, heading=None, step_m=None):
    if altitude1 is None:
        altitude1 = altitude0
    if heading is None:
        heading = bearing(a, b)
    if step_m is None:
        step_m = max(1.0, speed_kt * 0.514444)
    count = max(2, int(meters(a, b) / step_m) + 1)
    return [
        (
            lerp(a[0], b[0], i / (count - 1)),
            lerp(a[1], b[1], i / (count - 1)),
            lerp(altitude0, altitude1, i / (count - 1)),
            speed_kt,
            heading,
        )
        for i in range(count)
    ]


def hold(point, seconds, altitude, heading):
    return [(point[0], point[1], altitude, 0.0, heading)] * seconds


def ramp_speed(fixes, start_kt, end_kt):
    if len(fixes) < 2:
        return fixes
    return [
        (lat, lon, alt, lerp(start_kt, end_kt, i / (len(fixes) - 1)), heading)
        for i, (lat, lon, alt, _speed, heading) in enumerate(fixes)
    ]


def stitch(*parts):
    result = []
    for part in parts:
        if not part:
            continue
        result.extend(part if not result else part[1:])
    return result


def build_track():
    taxi = stitch(
        hold(START, 5, FIELD_ALT_M, bearing(START, HOLD_SHORT)),
        segment(START, HOLD_SHORT, TAXI_KT, FIELD_ALT_M, step_m=TAXI_STEP_M),
        hold(HOLD_SHORT, 4, FIELD_ALT_M, bearing(HOLD_SHORT, MID)),
        segment(HOLD_SHORT, MID, TAXI_KT, FIELD_ALT_M, step_m=TAXI_STEP_M),
        segment(MID, AFTER_CROSS, TAXI_KT, FIELD_ALT_M, step_m=TAXI_STEP_M),
        segment(AFTER_CROSS, PARALLEL_18, TAXI_KT, FIELD_ALT_M, step_m=TAXI_STEP_M),
        segment(PARALLEL_18, THR18, TAXI_KT, FIELD_ALT_M, step_m=TAXI_STEP_M),
        hold(THR18, HOLD_SEC, FIELD_ALT_M, HDG18),
    )

    takeoff_roll = ramp_speed(
        segment(THR18, ROTATE, 40.0, FIELD_ALT_M),
        12.0,
        55.0,
    )
    climb = segment(ROTATE, DEPART, 70.0, FIELD_ALT_M, 240.0, HDG18)
    crosswind = segment(DEPART, CROSSWIND, 75.0, 240.0, 360.0)
    downwind = segment(CROSSWIND, DOWNWIND_END, 75.0, 360.0, 360.0, HDG36)
    base = segment(DOWNWIND_END, BASE, 70.0, 360.0, 260.0)
    turn_final = segment(BASE, FINAL_START, 70.0, 260.0, 220.0, HDG18)
    final_long = segment(FINAL_START, FINAL_MID, 65.0, 220.0, 150.0, HDG18)
    final_short = segment(FINAL_MID, THR18, 60.0, 150.0, 105.0, HDG18)

    flare = []
    for i, altitude in enumerate([90.0, 65.0, 42.0, FIELD_ALT_M]):
        point = offset(THR18, 30.0 * i / 3, HDG18)
        flare.append(
            (point[0], point[1], altitude, 55.0 - 5.0 * i, HDG18)
        )

    rollout_end = offset(THR18, 160, HDG18)
    rollout = ramp_speed(
        segment(THR18, rollout_end, 40.0, FIELD_ALT_M),
        45.0,
        0.0,
    )

    return stitch(
        taxi,
        takeoff_roll,
        climb,
        crosswind,
        downwind,
        base,
        turn_final,
        final_long,
        final_short,
        flare,
        rollout,
        hold(rollout_end, HOLD_SEC, FIELD_ALT_M, HDG18),
    )


def nmea_lat(latitude):
    hemisphere = "N" if latitude >= 0 else "S"
    latitude = abs(latitude)
    degrees = int(latitude)
    return f"{degrees:02d}{(latitude - degrees) * 60:06.3f}", hemisphere


def nmea_lon(longitude):
    hemisphere = "E" if longitude >= 0 else "W"
    longitude = abs(longitude)
    degrees = int(longitude)
    return f"{degrees:03d}{(longitude - degrees) * 60:06.3f}", hemisphere


def sentence(body):
    checksum = 0
    for character in body:
        checksum ^= ord(character)
    return f"${body}*{checksum:02X}"


GSA = "GPGSA,A,3,01,02,03,04,05,06,07,08,09,10,11,12,1.0,1.0,1.0"


def write_nmea(fixes, filename):
    start = datetime(2026, 7, 24, 18, 0, 0, tzinfo=timezone.utc)
    lines = []
    for index, (lat, lon, altitude, speed, heading) in enumerate(fixes):
        timestamp = start + timedelta(seconds=index)
        time_text = timestamp.strftime("%H%M%S.000")
        date_text = timestamp.strftime("%d%m%y")
        lat_text, north_south = nmea_lat(lat)
        lon_text, east_west = nmea_lon(lon)
        lines.append(
            sentence(
                f"GPGGA,{time_text},{lat_text},{north_south},"
                f"{lon_text},{east_west},1,12,1.0,{altitude:.1f},M,0.0,M,,"
            )
        )
        lines.append(sentence(GSA))
        lines.append(
            sentence(
                f"GPRMC,{time_text},A,{lat_text},{north_south},"
                f"{lon_text},{east_west},{speed:05.1f},{heading:05.1f},"
                f"{date_text},000.0,W"
            )
        )
    with open(filename, "w") as output:
        output.write("\n".join(lines) + "\n")
    print(
        f"{filename}: {len(fixes)} fixes "
        f"(~{len(fixes) // 60}m {len(fixes) % 60}s)"
    )


if __name__ == "__main__":
    write_nmea(build_track(), "nmea_28m_cross_to_ld.txt")
