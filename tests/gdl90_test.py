"""Replay a GDL90 .bin to AvareX over UDP.

Generated scenarios (heartbeat-paced, e.g. gdl90_kbvy_land_rwy34.bin) play in
real time via gdl90_replay. Legacy captures still dump 256-byte chunks with
--fast.

    python3 gdl90_test.py gdl90_kbvy_land_rwy34.bin
    python3 gdl90_test.py adsb_dallas.bin --fast
"""
import sys

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--fast"]
    fast = "--fast" in sys.argv[1:]
    if not args:
        args = [input("Enter file name:")]
    if fast:
        import socket
        import time
        infile = args[0]
        print("Reading ADSB data from file: " + infile)
        while True:
            file = open(infile, "rb")
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            while True:
                data = file.read(256)
                if len(data) == 0:
                    print("rewind")
                    break
                sock.sendto(data, ("127.0.0.1", 43211))
                time.sleep(0.01)
            file.close()
            sock.close()
    else:
        from gdl90_replay import main
        sys.argv = [sys.argv[0], *args]
        raise SystemExit(main())
