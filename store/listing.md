# AvareX Store Listing Content

Ready-to-paste copy for the public app store listings, derived from `USER_MANUAL.md` and `pubspec.yaml`.

- **Google Play:** https://play.google.com/store/apps/details?id=com.apps4av.avaremp
- **Apple App Store / macOS:** https://apps.apple.com/us/app/avarex/id6502421523

Publishing locations (requires console login):

- Google Play Console: https://play.google.com/console → app → Grow → Store presence → Main store listing
- App Store Connect: https://appstoreconnect.apple.com → AvareX → version page

> Character limits are noted on each field. Counts should be re-verified before paste; store editors enforce them.

---

## Google Play

### Title (≤30 chars)

```
AvareX: Aviation EFB Maps
```

### Short description (≤80 chars)

```
Free EFB: charts, plates, weather, ADS-B traffic, flight plans. Pro from $5/mo
```

### Full description (≤4000 chars)

```
AvareX is a pilot's all-in-one electronic flight bag (EFB) from Apps4Av — the team behind Avare, rebuilt in Flutter. It runs on Android, iOS, Windows, macOS, Linux, and Raspberry Pi. The core EFB is free to download and fly; optional Pro features are just $5/month.

IMPORTANT: AvareX is not an FAA-certified GPS and must not be used as a sole means of navigation.

MOVING MAP
• VFR Sectional, TAC, Flyway, and Helicopter charts
• IFR Enroute Low, High, and Area charts
• Vector map with Class B/C/D airspace and special-use airspace (MOA, Restricted, Warning, Alert, Prohibited)
• Track-up or North-up, georeferenced ownship, range/speed/glide rings
• Movable instrument tiles (GS, ALT, track, ETA, ETE, distance, bearing and more)
• Topo and color-coded terrain/elevation layers
• Offline charts — download once, fly without internet

WEATHER
• METAR, TAF, PIREP, AIRMET, SIGMET, and TFRs, color-coded by flight category
• Animated internet radar and ADS-B/FIS-B NEXRAD
• Winds aloft wind-vector field and ceiling overlay at any altitude
• WPC surface/prog charts, SigWx, icing, turbulence, and winds/temps aloft products

ADS-B TRAFFIC & GPS
• Connect Stratux, Stratus, Echo, and other GDL90 receivers over Wi-Fi (UDP)
• Bluetooth ADS-B/GPS input (Android)
• Traffic targets with altitude offset, trend, and audible alerts
• Ground Proximity Warning System (GPWS) terrain alerts

PLATES & AIRPORTS
• Approach plates, airport diagrams, departures, STARs, CSUP
• Ownship drawn on georeferenced plates and diagrams
• Airport info, runways, NOTAMs, FBOs, and nearby alternates

FLIGHT PLANNING
• Build routes from airports, navaids, fixes, airways, and procedures
• Per-leg navigation log: heading, wind correction, ground speed, time, fuel
• Winds & terrain en-route profile
• IFR preferred routes and recent ATC routes
• File, brief, activate, and close FAA flight plans (1800wxbrief / LMFS)
• Send plans to NMEA 0183 devices over Bluetooth (Android)

AIRCRAFT & PERFORMANCE
• Built-in profiles (C152, C172S, C182T, PA-28, PA-44, Beech A36, Cirrus SR22, DA40) plus your own
• Takeoff, landing, and cruise performance with density altitude
• Weight & balance with interactive CG envelope (fixed-wing and helicopter)

LOGBOOK & TOOLS
• Digital logbook with currency tracking and CSV import/export
• Auto-create logbook entries from recorded flight tracks
• 2D/3D track viewer with terrain
• Checklists, handwriting notes with ATIS/CRAFT/clearance templates
• CAP Grid overlay for search and rescue

PRO SERVICES (optional subscription, $5/month, iOS/Android)
• Flight Intelligence AI assistant
• Cloud backup and sync
• Pilot Community groups
• Aircraft Scheduler for clubs and flight schools

Support and forum: https://groups.google.com/g/apps4av-forum

Aviation is inherently risky. Always cross-check with official sources and certified equipment.
```

### Metadata

- **Category:** Maps & Navigation (alt: Travel & Local)
- **Tags:** aviation, navigation, weather

---

## Apple App Store

### Name (≤30 chars)

```
AvareX
```

### Subtitle (≤30 chars)

```
Aviation EFB & Moving Map
```

### Promotional text (≤170 chars — editable anytime without a new build)

```
Free-to-fly EFB: FAA charts, approach plates, ADS-B traffic & weather, winds aloft, flight planning, logbook, and W&B — online or offline. Optional Pro from $5/mo.
```

### Keywords (≤100 chars, comma-separated, no spaces; not publicly visible)

```
aviation,efb,gps,ads-b,adsb,sectional,ifr,vfr,metar,taf,plates,nexrad,traffic,gdl90,stratux,pilot,navlog
```

### Description (≤4000 chars)

Reuse the Google Play full description above (it is within Apple's limit). The app is free to download, so "free to download and fly" is accurate on Apple too; keep the "$5/month" Pro note so the auto-renewing subscription is disclosed (Apple requires subscription terms to be stated).

### What's New (per version)

```
• Performance and stability improvements
• Updated charts, plates, and weather products
• Bug fixes
Thank you for flying with AvareX. Send feedback at the Apps4Av forum.
```

---

## Screenshots / Graphics Plan

Source images live in `assets/docs/screenshots/`. Suggested order (lead with the strongest 3):

1. `01_map_tab.png` — moving map with ownship + instruments (hero)
2. `02_map_layers_popup.png` — layers / weather overlays
3. `31_plate_tab.png` — georeferenced approach plate
4. `23_plan_navlog.png` — navigation log + winds/terrain
5. `13_aircraft_wnb.png` — weight & balance
6. `15_logbook_screen.png` — logbook
7. `09_aircraft_performance.png` — performance
8. `30_find_tab_search_kbos.png` — search / find

### Image requirements

**Google Play**
- App icon: 512×512 PNG
- Feature graphic: 1024×500 (required — not yet created)
- Phone screenshots: 2–8, min side ≥ 320 px, 16:9 or 9:16

**Apple App Store**
- Screenshots must match exact device sizes (6.9"/6.5" iPhone and 13" iPad)
- Existing PNGs are from the macOS build and likely will NOT pass Apple's dimension check — capture on real iPhone/iPad or build framed mockups at the correct resolution

---

## Notes / Disclaimers to keep in copy

- AvareX is **not** an FAA-certified GPS; not for sole-means navigation.
- The core EFB is **free to download and use**. Pro Services (Flight Intelligence AI, Cloud Backup/Sync, Pilot Community, Aircraft Scheduler) are **iOS/Android only** and require a **$5/month subscription** (auto-renewing; RevenueCat `Pro` entitlement). Disclose subscription terms in store copy.
- Internet required for downloads, weather, AI, FAA plan filing, and cloud backup; core navigation works offline once charts/databases are downloaded.
