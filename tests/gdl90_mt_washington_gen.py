#!/usr/bin/env python3
"""Generate a GDL90 stream that flies toward Mount Washington, NH.

For the PFD synthetic-terrain view. The airplane flies due north along the
summit meridian, level, so the peak stays dead ahead inside the ±6 NM
terrain mesh (`PfdTerrainSampler`).

The elevation tiles (zoom 10, chart index 6) peak at red value 82, which
decodes to 6234 ft. Ownship altitude is quantized to 25 ft of HAE, and
`Gps.clone` adds back the geo-table geoid (−28 m at 44N 71W), so the
closest MSL the app will show to 3000 ft is 2992 ft.

The slope under the old 4.3 NM start is already above 3000 ft, so this
track starts on the far mesh row, 6.0 NM south (`-6 + 12*r/14` at r=14).
That sample sits on the peak. 40 kt for 120 s ends 4.67 NM south, where
the centerline is still about 2850 ft — just under the airplane.

Per simulated second:
  0x00 heartbeat               1 Hz
  0x0A ownship                 1 Hz
  0x0B ownship geometric alt   1 Hz
  0x4C AHRS (iLevil layout)    5 Hz

Sign / unit notes (same as gdl90_kbvy_gen.py):
  * Ownship altitude is HAE. Encoded 2900 ft becomes 2992 ft MSL after the
    geoid correction.
  * AHRS yaw is magnetic. Declination is −14, so yaw = true heading + 14.
  * AHRS altitude is the MSL value the tape should show (2992).

Output: gdl90_mt_washington.bin
Replay: python3 gdl90_replay.py gdl90_mt_washington.bin
"""
from __future__ import annotations

import math
import os

GEOID_M = -28.0          # geo.height at 44N 71W
DECLINATION = -14.0      # geo.declination at 44N 71W (14 W)

# Summit pixel center in tiles/6/10 (red = 82).
PEAK_LAT = 44.27052567218034
PEAK_LON = -71.30367279052736
PEAK_FT = 82 * 80.4711845056 + -364.431597044586  # 6234.2 ft

FT_PER_DEG_LAT = 60 * 1852 * 3.28084
NM_FT = 6076.12

# Mesh row r=14: the far edge, 6 NM due south of the peak. Closer than
# about 4.6 NM the centerline rises through 3000 ft.
START_NM = -6 + 12 * 14 / 14
GS_KT = 40.0
DURATION_S = 120
PITCH_DEG = 2.0

# HAE that survives 25 ft quantization and the geoid step as 2992 ft MSL.
ALT_HAE_FT = 2900.0
ALT_MSL_FT = (ALT_HAE_FT * 0.3048 - GEOID_M) * 3.28084

AHRS_HZ = 5
OUTDIR = os.path.dirname(os.path.abspath(__file__))


def displayed_msl() -> float:
    return ALT_MSL_FT


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
    status1 = 0x81  # GPS valid, UAT initialized
    status2 = 0x01 | (((ts >> 16) & 1) << 7)
    return frame(bytes([0x00, status1, status2, ts & 0xFF, (ts >> 8) & 0xFF, 0, 0]))


def _deg24(deg: float) -> bytes:
    v = int(round(deg / (180.0 / (1 << 23)))) & 0xFFFFFF
    return v.to_bytes(3, "big")


def ownship(lat, lon, alt_hae_ft, gs_kt, track_true) -> bytes:
    alt = max(0, min(0xFFE, int(round((alt_hae_ft + 1000) / 25))))
    misc = 0x08 | 0x01  # airborne, true track angle
    vel = max(0, min(0xFFE, int(round(gs_kt))))
    vs = 0
    trk = int(round(track_true / 1.40625)) & 0xFF
    body = bytes([0x0A, 0x00, 0xA0, 0x00, 0x01])
    body += _deg24(lat) + _deg24(lon)
    body += bytes([alt >> 4, ((alt & 0xF) << 4) | misc, 0xA9])
    body += bytes([vel >> 4, ((vel & 0xF) << 4) | ((vs >> 8) & 0xF), vs & 0xFF])
    body += bytes([trk, 0x01]) + b"N12345  " + bytes([0x00])
    return frame(body)


def geo_alt(alt_hae_ft) -> bytes:
    return frame(bytes([0x0B]) + s16(alt_hae_ft / 5) + bytes([0x00, 0x0A]))


def ahrs(roll_app, pitch, yaw_mag, ias_kt, alt_msl_ft) -> bytes:
    body = bytes([0x4C, 0x45, 0x01, 0x01])
    body += s16(roll_app * 10) + s16(pitch * 10) + s16((yaw_mag % 360) * 10)
    body += s16(0)          # slip
    body += s16(0)          # turn trend
    body += s16(10)         # 1.0 g
    body += s16(ias_kt * 10)
    body += u16(alt_msl_ft + 5000)
    body += s16(0)          # vertical speed
    return frame(body)


def position(t_sec: int) -> tuple[float, float, float]:
    """Lat, lon, and range to the summit (NM) at this second. Heading 000 true."""
    flown_nm = GS_KT * t_sec / 3600.0
    range_nm = START_NM - flown_nm
    lat = PEAK_LAT - (range_nm * NM_FT) / FT_PER_DEG_LAT
    return lat, PEAK_LON, range_nm


def write(filename: str) -> None:
    out = bytearray()
    t0 = 14 * 3600  # 1400Z
    msl = round(displayed_msl())
    for i in range(DURATION_S):
        lat, lon, _ = position(i)
        out += heartbeat(t0 + i)
        out += ownship(lat, lon, ALT_HAE_FT, GS_KT, 0.0)
        out += geo_alt(ALT_HAE_FT)
        for k in range(AHRS_HZ):
            f = (i + k / AHRS_HZ)
            pitch = PITCH_DEG + 0.3 * math.sin(2 * math.pi * f / 7.0)
            bank = 0.8 * math.sin(2 * math.pi * f / 11.0)
            # mag = true - declination; true track is 000
            out += ahrs(-bank, pitch, 0.0 - DECLINATION, GS_KT, msl)
    with open(filename, "wb") as fh:
        fh.write(out)
    end_nm = position(DURATION_S - 1)[2]
    print(f"{filename}: {DURATION_S} s, {len(out)} bytes")
    print(f"  MSL {msl} ft ({PEAK_FT - msl:.0f} ft below the {PEAK_FT:.0f} ft tile peak)")
    print(f"  {START_NM:.3f} -> {end_nm:.3f} NM south of the summit, {GS_KT:.0f} kt, hdg 000 true")


if __name__ == "__main__":
    # The r=14 mesh row, built at the start fix, is the summit.
    along = -6 + 2 * 6 * 14 / 14
    assert abs(along - START_NM) < 1e-9
    lat0, lon0, _ = position(0)
    n = along * NM_FT
    hit_lat = lat0 + n / FT_PER_DEG_LAT
    assert abs(hit_lat - PEAK_LAT) < 1e-9
    assert abs(lon0 - PEAK_LON) < 1e-9
    path = os.path.join(OUTDIR, "gdl90_mt_washington.bin")
    write(path)
