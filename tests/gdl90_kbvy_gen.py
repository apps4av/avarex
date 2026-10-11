#!/usr/bin/env python3
"""Generate GDL90 streams that fly a 2 NM straight-in to a KBVY runway.

For testing the PFD synthetic runway (`PfdRunwaySelector` / `PfdPainter`).

Per simulated second the file carries:
  0x00 heartbeat               1 Hz  (replay pacing marker)
  0x0A ownship                 1 Hz  lat/lon, altitude, ground speed, true track
  0x0B ownship geometric alt   1 Hz
  0x4C AHRS (iLevil layout)    5 Hz  roll, pitch, magnetic heading, VSI, ...

120 s (2 min) from 2 NM on a 3 deg glidepath to a stop.

  0–80 s    2.0 → 0.4 NM    on centerline, 3 deg GS, 80 → 70 kt
 80–95 s    0.4 NM → thr    70 → 65 kt, 50 ft TCH
 95–105 s   flare / TD      ~1000 ft past threshold
105–120 s   rollout / stop  ~2500 ft down, hold at 0 kt

Sign / unit notes that matter to AvareX:
  * Ownship altitude is treated as HAE and geoid-corrected by `Gps.clone`
    (+28 m at KBVY from the `geo` table), so the encoded value is MSL - 92 ft.
  * AHRS yaw is read as MAGNETIC heading. Declination at KBVY in the `geo`
    table is -14.0, so yaw = true heading + 14.
  * AHRS roll sign follows the painter: positive rotates the horizon
    clockwise (left wing down). A right turn is therefore encoded negative.

Outputs:
  gdl90_kbvy_land_rwy34.bin
  gdl90_kbvy_land_rwy27.bin
Replay with gdl90_replay.py.
"""
from __future__ import annotations

import math
import os
from dataclasses import dataclass

GEOID_M = -28.0          # geo.height at 43N 71W
DECLINATION = -14.0      # geo.declination at 43N 71W (14 W)

FT_PER_DEG_LAT = 60 * 1852 * 3.28084
NM_FT = 6076.12
KT_FPS = 1.68781
G_FPS2 = 32.174
GS_DEG = 3.0
TCH_FT = 50.0

AHRS_HZ = 5
DURATION_S = 120
OUTDIR = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------- geometry
def bearing(a, b):
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl = math.radians(b[1] - a[1])
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return math.degrees(math.atan2(y, x)) % 360


@dataclass(frozen=True)
class Rwy:
    ident: str
    physical: tuple[float, float]
    far: tuple[float, float]
    end_elev_ft: float
    far_elev_ft: float
    length_ft: float
    displaced_ft: float

    @property
    def heading(self) -> float:
        return bearing(self.physical, self.far)

    def to_latlon(self, along_ft, cross_ft):
        """Inverse of PfdRunwayEnd.frameOf: runway frame -> lat/lon."""
        h = math.radians(self.heading)
        n = along_ft * math.cos(h) - cross_ft * math.sin(h)
        e = along_ft * math.sin(h) + cross_ft * math.cos(h)
        lat = self.physical[0] + n / FT_PER_DEG_LAT
        lon = self.physical[1] + e / (FT_PER_DEG_LAT * math.cos(math.radians(self.physical[0])))
        return lat, lon

    def elev(self, along_ft):
        t = min(1.0, max(0.0, along_ft / self.length_ft))
        return self.end_elev_ft + (self.far_elev_ft - self.end_elev_ft) * t

    def glidepath(self, along):
        if along >= self.displaced_ft:
            return self.elev(along)
        return self.elev(self.displaced_ft) + TCH_FT + (self.displaced_ft - along) * math.tan(math.radians(GS_DEG))


# airportrunways rows for KBVY (main.db). along=0 is the pavement end.
RWY34 = Rwy("34",
            (42.5813369722222, -70.9101480833333),
            (42.5919455833333, -70.9219251388889),
            82.1, 107.2, 5001, 0)
RWY27 = Rwy("27",
            (42.5832795833333, -70.90776175),
            (42.5797440555556, -70.9247545277778),
            91.2, 71.5, 4755, 250)


def smoothstep(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def lerp(a, b, t):
    return a + (b - a) * t


# ---------------------------------------------------------------- profile
# Times and distances from the landing threshold (not the pavement end).
# (t_sec, along_from_threshold_ft, cross_ft, gs_kt, pitch_deg)
_KEYS = (
    (  0,  -2.0 * NM_FT,  0.0, 80.0, 1.5),
    ( 80,  -0.4 * NM_FT,  0.0, 70.0, 1.5),
    ( 95,   0.0,          0.0, 65.0, 2.0),  # threshold, TCH
    (105, 1000.0,         0.0, 55.0, 6.0),  # flare / touchdown
    (112, 2200.0,         0.0, 15.0, 1.0),  # rollout
    (114, 2500.0,         0.0,  0.0, 1.0),  # stop
    (120, 2500.0,         0.0,  0.0, 1.0),
)

Fix = tuple[float, float, float, float, float, float, float]
# (lat, lon, alt_msl_ft, gs_kt, track_true, pitch_deg, bank_right_deg)


def build(rwy: Rwy) -> list[Fix]:
    keys = [(t, rwy.displaced_ft + a, c, gs, p) for t, a, c, gs, p in _KEYS]
    fixes: list[Fix] = []
    prev_track = None
    # 120 samples at t = 0..119; t = 120 is the same as the last key (stopped).
    for t in range(DURATION_S):
        i = 0
        while i + 1 < len(keys) and keys[i + 1][0] <= t:
            i += 1
        t0, a0, c0, gs0, p0 = keys[i]
        t1, a1, c1, gs1, p1 = keys[min(i + 1, len(keys) - 1)]
        u = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
        u = smoothstep(u)
        along = lerp(a0, a1, u)
        cross = lerp(c0, c1, u)
        gs = lerp(gs0, gs1, u)
        pitch = lerp(p0, p1, u)
        alt = rwy.glidepath(along)
        # Track from this sample toward the next second's position.
        t_n = min(t + 1, DURATION_S)
        j = i
        while j + 1 < len(keys) and keys[j + 1][0] <= t_n:
            j += 1
        tn0, an0, cn0 = keys[j][0], keys[j][1], keys[j][2]
        tn1, an1, cn1 = keys[min(j + 1, len(keys) - 1)][0:3]
        un = 0.0 if tn1 == tn0 else (t_n - tn0) / (tn1 - tn0)
        un = smoothstep(un)
        d_along = lerp(an0, an1, un) - along
        d_cross = lerp(cn0, cn1, un) - cross
        if abs(d_along) + abs(d_cross) < 1:
            track = rwy.heading
        else:
            track = (rwy.heading + math.degrees(math.atan2(d_cross, d_along))) % 360
        bank = _bank(gs, prev_track, track)
        lat, lon = rwy.to_latlon(along, cross)
        fixes.append((lat, lon, alt, gs, track, pitch, bank))
        prev_track = track
    return fixes


def _bank(gs_kt, prev_track, track):
    """Coordinated bank for the heading change over one second (deg, right+)."""
    if prev_track is None:
        return 0.0
    d = (track - prev_track + 540) % 360 - 180
    rate = math.radians(d)  # rad/s
    v = max(gs_kt, 40.0) * KT_FPS  # floor so the intercept bank is visible
    return math.degrees(math.atan(v * rate / G_FPS2))


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
    """payload = message id + body. Appends CRC (LSB first), byte-stuffs, flags."""
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
    status1 = 0x81  # GPS valid, UAT initialized
    status2 = 0x01 | (((ts >> 16) & 1) << 7)
    return frame(bytes([0x00, status1, status2, ts & 0xFF, (ts >> 8) & 0xFF, 0, 0]))


def _deg24(deg: float) -> bytes:
    v = int(round(deg / (180.0 / (1 << 23)))) & 0xFFFFFF
    return v.to_bytes(3, "big")


def ownship(lat, lon, alt_hae_ft, gs_kt, track_true, vs_fpm, airborne) -> bytes:
    alt = max(0, min(0xFFE, int(round((alt_hae_ft + 1000) / 25))))
    misc = (0x08 if airborne else 0x00) | 0x01  # true track angle
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
    body += s16(0)                        # slip
    body += s16(turn_rate_dps * 6 * 10)   # 6-second turn trend, degrees
    body += s16(10)                       # 1.0 g
    body += s16(ias_kt * 10)
    body += u16(alt_msl_ft + 5000)
    body += s16(vs_fpm)
    return frame(body)


def write(fixes: list[Fix], rwy: Rwy, filename: str):
    out = bytearray()
    t0 = 14 * 3600  # 1400Z
    geoid_ft = GEOID_M * 3.28084
    for i, (lat, lon, alt, gs, track, pitch, bank) in enumerate(fixes):
        nxt = fixes[min(i + 1, len(fixes) - 1)]
        vs_fpm = (nxt[2] - alt) * 60.0
        turn = (nxt[4] - track + 540) % 360 - 180
        airborne = alt > rwy.elev(rwy.displaced_ft) + 1 and gs > 30
        alt_hae = alt + geoid_ft  # Gps.clone adds back -geoid

        out += heartbeat(t0 + i)
        out += ownship(lat, lon, alt_hae, gs, track, vs_fpm, airborne)
        out += geo_alt(alt_hae)
        for k in range(AHRS_HZ):
            f = k / AHRS_HZ
            # interpolate attitude toward the next fix, add a little wobble
            p = lerp(pitch, nxt[5], f) + 0.3 * math.sin(2 * math.pi * (i + f) / 7.0)
            b = lerp(bank, nxt[6], f) + 0.8 * math.sin(2 * math.pi * (i + f) / 11.0)
            if gs == 0:
                p, b = pitch, 0.0
            yaw_true = track + ((nxt[4] - track + 540) % 360 - 180) * f
            yaw_mag = yaw_true - DECLINATION  # mag = true - declination
            out += ahrs(-b, p, yaw_mag, turn, gs, lerp(alt, nxt[2], f), vs_fpm)
    with open(filename, "wb") as fh:
        fh.write(out)
    print(f"{filename}: {len(fixes)} s (~{len(fixes) // 60}m {len(fixes) % 60}s), {len(out)} bytes")


if __name__ == "__main__":
    for rwy in (RWY34, RWY27):
        path = os.path.join(OUTDIR, f"gdl90_kbvy_land_rwy{rwy.ident.lower()}.bin")
        write(build(rwy), rwy, path)
