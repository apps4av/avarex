# 28M (Cranland) runway-awareness NMEA

File: `nmea_28m_cross_to_ld.txt` (~6 minutes 52 seconds)

Uses 28M runway 18/36: **1760 × 60 ft asphalt**, true bearing 164.3°.

## Sequence

1. Cross runway 18/36 at midfield
2. Taxi parallel to runway 18 and enter its threshold
3. Take off on runway 18
4. Fly a left pattern
5. Land on runway 18 and stop

## Playback

```bash
cd tests
python3 nmea_test.py nmea_28m_cross_to_ld.txt
```

The player sends one GPS fix per second to `127.0.0.1:49002`.

## Setup and approximate timing

- Be near **28M** so it is the closest airport
- Turn mute off
- Runway crossing approach begins around **5 seconds**
- Takeoff roll begins around **223 seconds**
- Runway-aligned final begins around **310 seconds**
- Touchdown begins around **395 seconds**

Only the crossing at the start should produce audio. Runway 18 also
intersects nothing here, so the takeoff, pattern, and landing must all be
silent.

## Regenerate and verify

```bash
python3 nmea_28m_gen.py
python3 sim_runway_awareness.py nmea_28m_cross_to_ld.txt 28M
```
