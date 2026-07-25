#!/usr/bin/env python3
"""Replay an NMEA file over UDP to AvareX (127.0.0.1:49002).

AvareX pops GPS once per second and StackWithOne discards anything received
in between, so this paces one *fix* per second: all sentences in a group are
sent back to back, then it sleeps. Sending faster makes the ownship teleport.

Usage:
  python3 nmea_test.py                              # prompts for file
  python3 nmea_test.py nmea_kbvy_foxtrot_rwy16.txt  # 1 fix/sec
  python3 nmea_test.py track.txt 0.5                # 2x speed
"""
import socket
import sys
import time

HOST, PORT = "127.0.0.1", 49002


def main():
    infile = sys.argv[1] if len(sys.argv) > 1 else input("Enter file name:")
    # seconds per fix; the app only consumes 1 fix/sec
    period = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0

    with open(infile, "rt") as f:
        lines = [ln for ln in (line.strip() for line in f) if ln]

    # group sentences into fixes: a new fix starts at each GGA (or RMC if no GGA)
    fixes, current = [], []
    for ln in lines:
        starts_fix = ln.startswith("$GPGGA") or (
            ln.startswith("$GPRMC") and not any(s.startswith("$GPGGA") for s in current)
        )
        if starts_fix and current:
            fixes.append(current)
            current = []
        current.append(ln)
    if current:
        fixes.append(current)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    print(f"{infile}: {len(fixes)} fixes at {period}s each (~{len(fixes) * period:.0f}s)")
    try:
        while True:
            for i, fix in enumerate(fixes):
                for ln in fix:
                    sock.sendto(bytes(ln + "\n", "UTF-8"), (HOST, PORT))
                if i % 15 == 0:
                    print(f"  t={i * period:.0f}s  fix {i}/{len(fixes)}")
                time.sleep(period)
            print("--- loop restart ---")
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()


if __name__ == "__main__":
    main()
