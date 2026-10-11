#!/usr/bin/env python3
"""Replay a GDL90 .bin to AvareX over UDP in real time.

Unlike gdl90_test.py (which streams 256-byte chunks as fast as possible),
this paces playback on the 0x00 heartbeat frames: every heartbeat marks one
second of flight, and the frames that follow it are spread evenly over that
second. Use it for generated scenarios where timing matters (PFD runway,
runway awareness, GPWS).

    python3 gdl90_replay.py gdl90_kbvy_land_rwy34.bin           # real time
    python3 gdl90_replay.py gdl90_kbvy_land_rwy34.bin --speed 4  # 4x
    python3 gdl90_replay.py file.bin --loop --host 192.168.1.20

AvareX listens on UDP 4000, 43211 and 49002; 43211 is the default here.
"""
from __future__ import annotations

import argparse
import socket
import sys
import time


def frames(data: bytes) -> list[bytes]:
    """Split on 0x7E flags; return complete frames with their flags re-added."""
    out = []
    for raw in data.split(b"\x7e"):
        if raw:
            out.append(b"\x7e" + raw + b"\x7e")
    return out


def seconds(frs: list[bytes]) -> list[list[bytes]]:
    """Group frames into one-second blocks that each start with a heartbeat."""
    blocks: list[list[bytes]] = []
    for f in frs:
        is_hb = len(f) > 2 and f[1] == 0x00
        if is_hb or not blocks:
            blocks.append([])
        blocks[-1].append(f)
    return blocks


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=43211)
    ap.add_argument("--speed", type=float, default=1.0, help="playback speed multiplier")
    ap.add_argument("--loop", action="store_true", help="restart at end of file")
    args = ap.parse_args()

    with open(args.file, "rb") as fh:
        blocks = seconds(frames(fh.read()))
    if not blocks:
        print("no GDL90 frames found", file=sys.stderr)
        return 1

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    dest = (args.host, args.port)
    period = 1.0 / max(0.01, args.speed)
    print(f"{args.file}: {len(blocks)} s of data -> {dest} at {args.speed}x")

    try:
        while True:
            start = time.monotonic()
            for i, block in enumerate(blocks):
                gap = period / len(block)
                for f in block:
                    sock.sendto(f, dest)
                    time.sleep(gap)
                # re-sync to the wall clock so sleep jitter does not accumulate
                due = start + (i + 1) * period
                now = time.monotonic()
                if due > now:
                    time.sleep(due - now)
                if i % 10 == 0:
                    print(f"\r{i:5d}/{len(blocks)} s", end="", flush=True)
            print()
            if not args.loop:
                break
            print("rewind")
    except KeyboardInterrupt:
        print()
    finally:
        sock.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
