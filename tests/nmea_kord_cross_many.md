# KORD (Chicago O'Hare) multi-runway crossing NMEA

File: `nmea_kord_cross_many.txt`

Northbound taxi along midfield longitude **−87.90763**, crossing every
parallel E–W runway plus the **04L/22R** diagonal that intersects that line.

## Crossing order (south → north)

1. **10R / 28L**
2. **10C / 28C**
3. **10L / 28R**
4. **09R / 27L**
5. **04L / 22R** (diagonal)
6. **09C / 27C**
7. **09L / 27R**

04R/22L does not intersect this taxi line and is not crossed.

## Playback

```bash
cd tests
python3 nmea_test.py nmea_kord_cross_many.txt
```

One GPS fix per second to `127.0.0.1:49002`.

## Setup and expected behavior

- Be near **KORD** so it is the closest airport
- Mute **off**
- One **"approaching runway"** callout per runway as you near each centerline
- 04L and 09C are close together; callouts may be nearly back-to-back

## Regenerate and verify

```bash
python3 nmea_kord_gen.py
python3 sim_runway_awareness.py nmea_kord_cross_many.txt KORD
```
