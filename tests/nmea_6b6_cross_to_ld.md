# 6B6 (Minute Man) runway awareness NMEA

File: `nmea_6b6_cross_to_ld.txt` (~8.5 min)

Airport **6B6** — RWY 03/21 (3110 × 48 asphalt), plus intersecting turf 12/30.

## Sequence
1. Taxi from ramp side → **cross RWY 03/21** at midfield
2. Taxi to RWY 03 threshold → hold
3. **Takeoff** roll / climb on 03
4. Left pattern
5. **Landing** final on 03 → touchdown

## Play
```bash
cd tests
python3 nmea_test.py nmea_6b6_cross_to_ld.txt
```

1 fix/sec to `127.0.0.1:49002`.

## Test setup
- Be near **6B6** so it is the closest airport
- Mute **off**
- Crossing callout ~t=20–50 s
- The takeoff, pattern, and landing that follow must stay silent — rolling
  aligned on a runway is not a crossing

## Regenerate
```bash
python3 nmea_6b6_gen.py
python3 sim_runway_awareness.py nmea_6b6_cross_to_ld.txt 6B6
```
