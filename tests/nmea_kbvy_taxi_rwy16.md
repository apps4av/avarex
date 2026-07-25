# KBVY runway awareness NMEA tracks

Tracks for testing `RunwayAwareness` crossing callouts. The takeoff and
landing segments are negative tests: they must stay silent.

| File | Length | What it covers |
|---|---|---|
| `nmea_kbvy_foxtrot_rwy16.txt` | ~1.5 min | Alpha → Foxtrot → RWY 16 (crossing) |
| `nmea_kbvy_to_ld_rwy16.txt` | ~5.5 min | Hold RWY 16 → **takeoff** → left pattern → **land** 16 |
| `nmea_kbvy_taxi_rwy16.txt` | ~12 min | Full: taxi / midfield cross / Foxtrot / TO / pattern / LD |

## Timing
AvareX pops GPS **once per second** and discards anything in between
(`StackWithOne`). Playback must send **one fix per second**.

```bash
cd tests
python3 nmea_test.py nmea_kbvy_to_ld_rwy16.txt          # TO + LD
python3 nmea_test.py nmea_kbvy_foxtrot_rwy16.txt         # crossing only
```

## Test setup
- Be near **KBVY** so it is the closest airport
- Mute **off**
- Any aircraft — the crossing callout does not depend on performance data

## `nmea_kbvy_to_ld_rwy16.txt` timeline (approx.)
| t | Phase | Expect |
|---|---|---|
| 0–10 s | Hold on RWY 16 threshold | — |
| 10–50 s | Takeoff roll, accelerating, runway-aligned | silent |
| 50–90 s | Liftoff / climb runway heading | silent |
| 90–240 s | Left pattern (crosswind / downwind / base) | silent |
| 240–300 s | Final RWY 16, descending | silent |
| 300 s+ | Touchdown / stop | silent |

## Regenerate / offline check
```bash
python3 nmea_kbvy_gen.py
python3 sim_runway_awareness.py nmea_kbvy_to_ld_rwy16.txt KBVY
```
