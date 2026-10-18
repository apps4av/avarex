#!/usr/bin/env python3
"""Generate a GDL90 stream: takeoff KSLC runway 16L, then east at the Wasatch.

The Wasatch front is east of the field. 16L departs south (true heading 175).
After liftoff the airplane makes a climbing left turn to 090 and flies toward
the mountains. The 3D airspace picture stays 25 NM; this track does not change that.

Runway ends and elevations are `airportrunways` for KSLC 16L/34R.
Geoid and declination are the `geo` row at 41 N, 112 W: height −15 m, declination 11 E.

Sign / unit notes (same as gdl90_kbvy_gen.py):
  * Ownship altitude is HAE. Gps.clone subtracts the geoid, so the encoded
    value is MSL + (−15 m).
  * AHRS yaw is magnetic. Declination is +11, so yaw = true heading − 11.
  * AHRS roll: positive is left wing down. A left turn is encoded positive.

4 minutes:
  0–40 s    takeoff roll on 16L, rotate
 40–60 s    climb on runway heading
 60–100 s   climbing left turn to east
100–240 s   east toward the mountains, still climbing

Output: gdl90_kslc_takeoff_east.bin
Replay: python3 gdl90_replay.py gdl90_kslc_takeoff_east.bin
"""
from __future__ import annotations

import math
import os

GEOID_M = -15.0          # geo.height at 41N 112W
DECLINATION = 11.0       # geo.declination, 11 E

# 16L threshold (north end) and far end, from airportrunways.
THR = (40.8074527222222, -111.976932138889)
FIELD_FT = 4229.1

FT_PER_DEG_LAT = 60 * 1852 * 3.28084
KT_FPS = 1.68781
G_FPS2 = 32.174

AHRS_HZ = 5
DURATION_S = 240
OUTDIR = os.path.dirname(os.path.abspath(__file__))

# (t_sec, gs_kt, track_true, alt_msl_ft, pitch_deg)
_KEYS = (
    (  0,   0.0, 175.0, 4229.0, 0.0),
    ( 40,  75.0, 175.0, 4235.0, 10.0),  # rotate
    ( 60,  90.0, 175.0, 4800.0,  8.0),  # climb on runway heading
    (100, 100.0,  90.0, 5600.0,  6.0),  # left turn complete, east
    (240, 110.0,  90.0, 7500.0,  5.0),  # toward the Wasatch
)

Fix = tuple[float, float, float, float, float, float, float]
# (lat, lon, alt_msl_ft, gs_kt, track_true, pitch_deg, bank_right_deg)


def smoothstep(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def lerp(a, b, t):
    return a + (b - a) * t


def ang_delta(a, b):
    return (b - a + 540) % 360 - 180


def sample(t):
    i = 0
    while i + 1 < len(_KEYS) and _KEYS[i + 1][0] <= t:
        i += 1
    t0, gs0, trk0, alt0, p0 = _KEYS[i]
    t1, gs1, trk1, alt1, p1 = _KEYS[min(i + 1, len(_KEYS) - 1)]
    u = 0.0 if t1 == t0 else smoothstep((t - t0) / (t1 - t0))
    track = (trk0 + ang_delta(trk0, trk1) * u) % 360
    return lerp(gs0, gs1, u), track, lerp(alt0, alt1, u), lerp(p0, p1, u)


def move(lat, lon, track, gs_kt, dt):
    dist = gs_kt * KT_FPS * dt
    h = math.radians(track)
    n = dist * math.cos(h)
    e = dist * math.sin(h)
    lat += n / FT_PER_DEG_LAT
    lon += e / (FT_PER_DEG_LAT * math.cos(math.radians(lat)))
    return lat, lon


def bank_for(gs_kt, d_track):
    """Coordinated bank for a heading change over one second (deg, right+)."""
    rate = math.radians(d_track)
    v = max(gs_kt, 40.0) * KT_FPS
    return math.degrees(math.atan(v * rate / G_FPS2))


def build() -> list[Fix]:
    lat, lon = THR
    fixes: list[Fix] = []
    prev_track = None
    for t in range(DURATION_S):
        gs, track, alt, pitch = sample(t)
        _, track_n, _, _ = sample(min(t + 1, DURATION_S))
        d_track = ang_delta(track, track_n) if prev_track is not None else 0.0
        bank = 0.0 if gs < 40 else bank_for(gs, d_track)
        fixes.append((lat, lon, alt, gs, track, pitch, bank))
        lat, lon = move(lat, lon, track, gs, 1.0)
        prev_track = track
    return fixes


# ---------------------------------------------------------------- GDL90
def _crc_table():
    table = []
    for i in range(256):
        crc = i << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if (crc & 0x8000) else (crc << 1)
            crc &= 0xFFFF
        table.append(crc)
    return table


CRC_TABLE = _crc_table()


def crc16(data: bytes) -> int:
    crc = 0
    for b in data:
        crc = (CRC_TABLE[crc >> 8] ^ (crc << 8) ^ b) & 0xFFFF
    return crc


def frame(payload: bytes) -> bytes:
    c = crc16(payload)
    data = payload + bytes([c & 0xFF, c >> 8])
    out = bytearray([0x7E])
    for b in data:
        if b in (0x7D, 0x7E):
            out += bytes([0x7D, b ^ 0x20])
        else:
            out.append(b)
    out.append(0x7E)
    return bytes(out)


def s16(v: float) -> bytes:
    i = max(-32767, min(32767, int(round(v))))
    return (i & 0xFFFF).to_bytes(2, "big")


def u16(v: float) -> bytes:
    return max(0, min(0xFFFF, int(round(v)))).to_bytes(2, "big")


def heartbeat(t_sec: int) -> bytes:
    ts = t_sec & 0x1FFFF
    status1 = 0x81
    status2 = 0x01 | (((ts >> 16) & 1) << 7)
    return frame(bytes([0x00, status1, status2, ts & 0xFF, (ts >> 8) & 0xFF, 0, 0]))


def _deg24(deg: float) -> bytes:
    v = int(round(deg / (180.0 / (1 << 23)))) & 0xFFFFFF
    return v.to_bytes(3, "big")


def ownship(lat, lon, alt_hae_ft, gs_kt, track_true, vs_fpm, airborne) -> bytes:
    alt = max(0, min(0xFFE, int(round((alt_hae_ft + 1000) / 25))))
    misc = (0x08 if airborne else 0x00) | 0x01
    vel = max(0, min(0xFFE, int(round(gs_kt))))
    vs = max(-2047, min(2047, int(round(vs_fpm / 64)))) & 0xFFF
    trk = int(round(track_true / 1.40625)) & 0xFF
    body = bytes([0x0A, 0x00, 0xA0, 0x00, 0x01])
    body += _deg24(lat) + _deg24(lon)
    body += bytes([alt >> 4, ((alt & 0xF) << 4) | misc, 0xA9])
    body += bytes([vel >> 4, ((vel & 0xF) << 4) | ((vs >> 8) & 0xF), vs & 0xFF])
    body += bytes([trk, 0x01]) + b"N12345  " + bytes([0x00])
    return frame(body)


def geo_alt(alt_hae_ft) -> bytes:
    return frame(bytes([0x0B]) + s16(alt_hae_ft / 5) + bytes([0x00, 0x0A]))


def ahrs(roll_app, pitch, yaw_mag, turn_rate_dps, ias_kt, alt_msl_ft, vs_fpm) -> bytes:
    body = bytes([0x4C, 0x45, 0x01, 0x01])
    body += s16(roll_app * 10) + s16(pitch * 10) + s16((yaw_mag % 360) * 10)
    body += s16(0)
    body += s16(turn_rate_dps * 6 * 10)
    body += s16(10)
    body += s16(ias_kt * 10)
    body += u16(alt_msl_ft + 5000)
    body += s16(vs_fpm)
    return frame(body)


def write(fixes: list[Fix], filename: str):
    out = bytearray()
    t0 = 14 * 3600
    geoid_ft = GEOID_M * 3.28084
    for i, (lat, lon, alt, gs, track, pitch, bank) in enumerate(fixes):
        nxt = fixes[min(i + 1, len(fixes) - 1)]
        vs_fpm = (nxt[2] - alt) * 60.0
        turn = ang_delta(track, nxt[4])
        airborne = alt > FIELD_FT + 20 and gs > 60
        alt_hae = alt + geoid_ft
        out += heartbeat(t0 + i)
        out += ownship(lat, lon, alt_hae, gs, track, vs_fpm, airborne)
        out += geo_alt(alt_hae)
        for k in range(AHRS_HZ):
            f = k / AHRS_HZ
            p = lerp(pitch, nxt[5], f) + 0.3 * math.sin(2 * math.pi * (i + f) / 7.0)
            b = lerp(bank, nxt[6], f) + 0.8 * math.sin(2 * math.pi * (i + f) / 11.0)
            if gs < 5:
                p, b = pitch, 0.0
            yaw_true = (track + turn * f) % 360
            yaw_mag = yaw_true - DECLINATION
            out += ahrs(-b, p, yaw_mag, turn, gs, lerp(alt, nxt[2], f), vs_fpm)
    with open(filename, "wb") as fh:
        fh.write(out)
    end = fixes[-1]
    east_nm = (end[1] - THR[1]) * FT_PER_DEG_LAT * math.cos(math.radians(THR[0])) / 6076.12
    north_nm = (end[0] - THR[0]) * FT_PER_DEG_LAT / 6076.12
    print(f"{filename}: {len(fixes)} s, {len(out)} bytes")
    print(f"  start {fixes[0][0]:.5f}, {fixes[0][1]:.5f}  {fixes[0][2]:.0f} ft")
    print(f"  end   {end[0]:.5f}, {end[1]:.5f}  {end[2]:.0f} ft  track {end[4]:.0f}")
    print(f"  {east_nm:.1f} NM east, {north_nm:.1f} NM north of the 16L threshold")


if __name__ == "__main__":
    path = os.path.join(OUTDIR, "gdl90_kslc_takeoff_east.bin")
    write(build(), path)
