#!/usr/bin/env python3
"""Generate a KORD multi-runway crossing NMEA track.

Taxis north along lon ≈ −87.90763 (midfield of 10L/28R), crossing every
parallel E–W runway plus the 04L/22R diagonal that intersects that line:

  10R/28L → 10C/28C → 10L/28R → 09R/27L → 04L/22R → 09C/27C → 09L/27R

AvareX consumes one GPS fix per second. Expect one "approaching runway"
callout per runway (once until clear).
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone

# Intersection latitudes on lon = −87.90763 (from airportrunways).
TAXI_LON = -87.90763
CROSSINGS = [
    # (name, lat at intersection)
    ("10R", 41.957234),
    ("10C", 41.965740),
    ("10L", 41.969033),
    ("09R", 41.983898),
    ("04L", 41.987347),  # diagonal 04L/22R
    ("09C", 41.988307),
    ("09L", 42.002831),
]

FIELD_ALT_M = 207.0  # 680 ft ARP
# Cruise between runways; slow near each hold-short so RMC still ≥ ~4 kt.
TAXI_KT = 18.0
CROSS_KT = 5.8
TAXI_STEP_M = TAXI_KT * 0.514444
CROSS_STEP_M = 3.0
HOLD_SEC = 3
PAD_M = 100.0  # hold-short / clear distance from centerline

HDG_NORTH = 0.0
HDG_SOUTH = 180.0

Fix = tuple[float, float, float, float, float]


def offset_lat(lat, distance_m, heading):
    """Move along a meridian (heading 0 or 180) at fixed lon."""
    sign = 1.0 if heading < 90 or heading > 270 else -1.0
    return lat + sign * distance_m / 111320.0


def lerp(a, b, fraction):
    return a + (b - a) * fraction


def meters_ns(lat_a, lat_b):
    return abs(lat_b - lat_a) * 111320.0


def segment_ns(lat_a, lat_b, speed_kt, step_m=None, heading=None):
    if heading is None:
        heading = HDG_NORTH if lat_b >= lat_a else HDG_SOUTH
    if step_m is None:
        step_m = max(1.0, speed_kt * 0.514444)
    count = max(2, int(meters_ns(lat_a, lat_b) / step_m) + 1)
    return [
        (
            lerp(lat_a, lat_b, i / (count - 1)),
            TAXI_LON,
            FIELD_ALT_M,
            speed_kt,
            heading,
        )
        for i in range(count)
    ]


def hold(lat, seconds, heading):
    return [(lat, TAXI_LON, FIELD_ALT_M, 0.0, heading)] * seconds


def stitch(*parts):
    result = []
    for part in parts:
        if not part:
            continue
        result.extend(part if not result else part[1:])
    return result


def build_track():
    parts: list[list[Fix]] = []
    # Start south of the first runway.
    start_lat = offset_lat(CROSSINGS[0][1], PAD_M + 40, HDG_SOUTH)
    parts.append(hold(start_lat, 5, HDG_NORTH))

    prev_clear = start_lat
    for name, cross_lat in CROSSINGS:
        hold_short = offset_lat(cross_lat, PAD_M, HDG_SOUTH)
        clear = offset_lat(cross_lat, PAD_M, HDG_NORTH)

        # Fast taxi up to hold-short.
        parts.append(
            segment_ns(prev_clear, hold_short, TAXI_KT, step_m=TAXI_STEP_M)
        )
        parts.append(hold(hold_short, HOLD_SEC, HDG_NORTH))
        # Slow across the centerline and clear the pavement.
        parts.append(
            segment_ns(hold_short, clear, CROSS_KT, step_m=CROSS_STEP_M)
        )
        parts.append(hold(clear, 2, HDG_NORTH))
        prev_clear = clear

    # Brief stop north of 09L.
    parts.append(hold(prev_clear, 6, HDG_NORTH))
    return stitch(*parts)


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
    start = datetime(2026, 7, 25, 15, 0, 0, tzinfo=timezone.utc)
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
    print("crossing order (south → north):")
    for name, lat in CROSSINGS:
        print(f"  {name} @ {lat:.6f}")


if __name__ == "__main__":
    write_nmea(build_track(), "nmea_kord_cross_many.txt")
