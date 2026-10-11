# KBVY PFD runway GDL90 tracks

2-minute (120 s) straight-in from 2 NM, on the 3° glidepath / centerline, for
the PFD synthetic runway.

| File | Runway | Notes |
|---|---|---|
| `gdl90_kbvy_land_rwy34.bin` | 34 | no displaced threshold |
| `gdl90_kbvy_land_rwy27.bin` | 27 | 250 ft displaced threshold |

## Replay

AvareX pops GPS **once per second**. Use the heartbeat-paced player (default):

```bash
cd tests
python3 gdl90_replay.py gdl90_kbvy_land_rwy27.bin
# or
python3 gdl90_test.py gdl90_kbvy_land_rwy34.bin
```

`gdl90_test.py --fast` dumps raw chunks and finishes in about a second — do not
use that for this file.

## Test setup

- Enable the **PFD** layer
- GPS source **Auto** or **External** (not Internal)
- Be near **KBVY** so it is the closest airport, or set the plan to KBVY

## Timeline

| t | Phase | Expect on PFD |
|---|---|---|
| 0–80 s | 2.0 → 0.4 NM, on GS / centerline, 80 → 70 kt | runway head-on; threshold, 1000-ft bars, centerline |
| 80–95 s | 0.4 NM → threshold | 50 ft TCH, ident + distance |
| 95–120 s | flare, touchdown, stop ~2500 ft past threshold | pavement fills the view, then stops |

## Regenerate

```bash
python3 gdl90_kbvy_gen.py
```
