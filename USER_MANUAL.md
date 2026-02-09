# AvareX User Manual 
This manual is generated from the current app codebase and focuses on:

- **What features exist**
- **How to reach them in the UI**
- **What each feature does**
- **Platform-specific availability**

---

## 1) Before You Start

### 1.1 Safety and intended use

AvareX displays an in-app Terms of Use during onboarding that states this is **not an FAA-certified GPS** and must not be relied on as a sole safety-critical system.

### 1.2 Internet and GPS requirements

- Internet is required for:
  - chart/database downloads
  - weather/doc products
  - Flight Intelligence (AI)
  - FAA plan services / cloud backup
- GPS can come from:
  - internal device GPS
  - external ADS-B / GPS streams over **UDP ports 4000, 43211, 49002**
  - external Bluetooth stream (Android IO screen)

### 1.3 First-run onboarding checklist

On first run, complete onboarding pages:

1. **Sign Terms of Use** (required to continue).
2. Select **Day/Night theme**.
3. Select units:
   - Maritime (NM/knots/feet)
   - Imperial (SM/MPH/feet)
4. Confirm GPS permissions/settings.
5. Open **Download** and get at least **Databases** (recommended before use).
6. Optional: register your 1800wxbrief.com email for FAA flight-plan workflows.

You can reopen onboarding later from the main drawer header icon.

---

## 2) Platform Feature Availability

| Feature | Availability |
|---|---|
| Core app (Map/Plate/Plan/Find, downloads, documents, aircraft, checklist, W&B, logbook) | All supported platforms |
| Bluetooth IO screen | **Android only** |
| Plan Transfer to Garmin Connext | **Android only** (through Bluetooth IO) |
| Pro Services entry (Flight Intelligence + Backup/Sync) | **iOS and Android** |
| Donate menu item | Not shown on iOS/macOS |
| PDF viewing in Documents | Not shown on Linux |
| File sharing from Documents/Logbook export | Not shown on Linux |

---

## 3) Main Navigation

After onboarding, the app opens to `MainScreen` with:

- **Bottom tabs**: `MAP`, `PLATE`, `PLAN`, `FIND`
- **Left drawer menu** (opened by `Menu` button on map)
- **Warnings drawer** (right side, opened by red warning icon when issues exist)

### 3.1 Bottom tabs

1. **MAP** — moving map, overlays, weather, traffic, route visualization, tools.
2. **PLATE** — approach plates/airport diagrams/CSUP with ownship overlay.
3. **PLAN** — build, edit, brief/file, and manage flight plans.
4. **FIND** — search destinations, recent list, nearest-airport shortcuts.

### 3.2 Drawer menu entries

Open from MAP with **Menu** button (bottom-left):

- Download
- Documents
- Aircraft
- Check Lists
- W&B
- Log Book
- IO (Android only)
- Donate (where available)

---

## 4) MAP Tab (Primary Flight Display + Map Tools)

### 4.1 How to access

Tap bottom tab **MAP**.

### 4.2 Core interactions

- Pan/zoom map
- Track-up or North-up orientation toggle
- Long-press behavior:
  - if ruler mode OFF: opens destination popup near pressed location
  - if ruler mode ON: drops ruler points for distance/bearing measurement
- Tap/long-press map also dismisses pop-up toasts

### 4.3 Map controls (buttons and menus)

### Top-right
- **Pro icon** (iOS/Android): opens Pro Services login/paywall flow.
- **Red warning icon** (if active): opens troubleshooting drawer.

### Bottom center
- **Center** button:
  - Tap: recenter on ownship (current zoom)
  - Long press: recenter and zoom to chart max zoom

### Bottom-left
- **Menu** button: opens drawer list (Download, Documents, etc.)

### Bottom-right control row
- **Ruler (compass icon)**: toggle measure mode; long-press map to add points.
- **North-up / Track-up toggle**: switches orientation mode.
- **Rubber banding toggle**: enables dragging route waypoints directly on map.
- **Notes icon**: opens handwriting Notes screen.
- **Chart type popup**: selects chart source type.
- **Layers popup**: per-layer on/off via opacity slider.

### Traffic-only controls (show when Traffic layer > 0)
- **Audio mute/unmute**
- **Traffic volume puck size** cycles: `S`, `M`, `L`
  - S: 20 aircraft, 3000 ft, 10 NM
  - M: 200 aircraft, 6000 ft, 50 NM
  - L: 1000 aircraft, 30000 ft, 500 NM

### Altitude slider (left side)
- Appears when **Ceiling** or **Wind Vectors** layer is on.
- Adjusts planning altitude used by those overlays.

### 4.4 Map chart types

Selectable map chart types:

- Sectional
- TAC
- IFR Low
- IFR High
- IFR Area
- Helicopter
- Flyway

### 4.5 Map layers and what they do

Layer list from settings (with per-layer opacity):

- **Nav**: route lines, runway depiction, waypoint markers/labels, ownship symbol.
- **Circles**: range rings (10/5/2 NM), speed ring, glide circle + labels.
- **Chart**: downloaded chart tiles (offline chart base).
- **OSM**: OpenStreetMap online base.
- **OpenAIP**: OpenAIP online aviation layer.
- **Topo**: USGS topo online base.
- **Elevation**: downloaded elevation tiles.
- **Weather**: METAR/TAF/AIREP/AIRSIGMET symbols + ADS-B weather overlays.
- **Radar**: internet radar animation tiles.
- **TFR**: temporary flight restriction shapes/markers.
- **Wind Vectors**: wind vector field overlay (altitude-dependent).
- **Ceiling**: ceiling overlay (altitude-dependent).
- **Plate**: georeferenced plate overlay on map (when loaded).
- **Traffic**: traffic symbols, relative orientation; audible alerts integration.
- **Obstacles**: obstacle markers.
- **Tape**: distance tape labels from ownship upward.
- **GeoJSON**: imported user GeoJSON polygons/markers.
- **PFD**: inset synthetic PFD panel.
- **Tracks**: ownship breadcrumb/polyline.

Notes:

- OSM and Topo are mutually reduced by UI logic (enabling one can disable the other).
- Chart and OpenAIP are similarly managed for performance.
- Turning **Tracks** layer OFF saves a KML track file into Documents and clears active track recording.

### 4.6 Instrument strip (top-left)

Reorderable instrument tiles include:

- GS, ALT, MT, PRV, NXT, DIS, BRG, GEL, ETA, ETE, VSR, UPT, DNT, UTC, SRC, FLT

Interactions:

- PRV/NXT: jump previous/next waypoint
- UPT/DNT: start/stop timers
- FLT: reset tracked flight time
- Dropdown menu allows tile expand/contract and help text

---

## 5) Destination Popup (Map Long-Press or Find Tap)

### 5.1 How to access

- Long press on map (when ruler mode is off), or
- Tap an item in FIND list

### 5.2 Top action buttons

- **→D**: set Direct-To destination, center map there, return to map
- **+Plan**: insert destination into current plan
- **Plates** (airport only): jump to PLATE tab at that airport

### 5.3 Information pages (shown when data exists)

Possible tabs:

- **Main**: destination summary
- **AD**: airport diagram/runway depiction
- **METAR**: METAR + TAF text
- **NOTAM**: fetched NOTAM list
- **SUA**: special-use airspace data
- **Wind**: nearest winds-aloft station data
- **ST**: sounding chart/image
- **Business**: nearby business/FBO list (with AI Details button when Pro enabled)

If nearby alternatives exist, a horizontal “Nearby” selector appears.

---

## 6) PLATE Tab

### 6.1 How to access

- Bottom tab **PLATE**, or
- from destination popup using **Plates**

### 6.2 What it does

- Displays downloaded plates/diagrams/CSUP
- Draws ownship and heading on georeferenced plates
- Can overlay selected business/FBO marker on airport diagrams
- Supports zoom/pan via InteractiveViewer

### 6.3 Controls

- **Airport selector** (bottom-right): choose airport
- **Plate selector** (bottom-left): choose plate within airport
- **Procedure menu** (plus icon near bottom-right):
  - show procedure profile
  - `+Plan` adds procedure waypoint sequence to plan
- **Instrument strip show/hide** toggle (top-right)
- **Profile close (X)** closes procedure profile card

### 6.4 Terrain caution overlay on plates

When map **Elevation** layer has opacity > 0, plate rendering can include colored terrain risk cells:

- yellow/red overlays based on aircraft altitude margins above terrain.

### 6.5 Automatic behavior on landing

Flight-state logic can auto-switch plate context to nearest airport diagram after landing (if available).

---

## 7) PLAN Tab

### 7.1 How to access

Tap bottom tab **PLAN**.

### 7.2 Main plan editor

- Reorderable waypoint list (drag to reorder)
- Swipe row to delete waypoint
- Tap row to set current waypoint
- Header row shows plan-wide calculated totals

Bottom controls:

- **Actions** button opens Plan Actions screen
- **ASpd** field: true airspeed used in calculations
- **GPH** field: fuel burn
- **Alt** field: plan altitude
- **Forecast horizon** selector: 06H / 12H / 24H
- **Fuel icon** opens full-screen Navigation Log

### 7.3 Navigation Log dialog

Includes:

- per-leg log grid
- wind field diagram en route
- terrain profile en route
- copy plan to clipboard button

### 7.4 Plan Actions screen

Sub-pages:

### A) Load & Save
- Save current plan by name
- Load saved plan
- Load reversed
- Delete saved plan

### B) Create
- **Create As Entered**: parse typed route string
- **Create IFR Preferred Route**: build from preferred route service
- **Show IFR ATC Routes**: show recent ATC routes between departure/destination

### C) Brief & File (FAA)
- Detailed ICAO form fields
- Quick-fill buttons from current plan and stored aircraft
- Buttons:
  - **Get Email Brief**
  - **Send to FAA**

Requires configured 1800wxbrief-compatible account email.

### D) Manage (FAA)
- Retrieve filed plans
- State-aware actions:
  - Cancel (for non-active)
  - Close (for active)
  - Depart / activate with chosen time (for proposed)

### E) Transfer (Android)
- Garmin Connext transfer workflow
- Requires Bluetooth connection in IO screen
- Sends current plan to Garmin device via NMEA RTE/WPL sequence
- Minimum 2 waypoints required

---

## 8) FIND Tab

### 8.1 How to access

Tap bottom tab **FIND**.

### 8.2 What it does

- Search destinations by text
- Browse:
  - Recent
  - Nearest
  - Nearest 2K (runway >= 2000)
  - Nearest 4K (runway >= 4000)

### 8.3 Row actions

- Tap row: opens destination popup/details
- Right-side bearing@distance button: centers map on item and switches to MAP
- Swipe to delete recent entry
- For GPS-type recents, you can edit custom facility name

---

## 9) Drawer Features

### 9.1 Download

Open: **Menu → Download**

Purpose:

- install/update/delete downloadable data sets by chart category and region
- monitor progress with per-item progress ring and stop button

Controls:

- Tap chart item to cycle desired action (download/update/delete/none)
- **Start** executes queued actions
- Toggle **This Cycle / Next Cycle**
- Toggle **Main Server / Backup Server**
- Info map icon shows regional coverage image

Major download categories include:

- Databases (required for core nav data)
- Sectional, TAC, IFR Low/High/Area, Helicopter, Flyway
- Plates, CSUP, Elevation

### 9.2 Documents

Open: **Menu → Documents**

Includes:

- Built-in weather/prog chart products (WPC, SigWx, AIRMETs, radar, winds/temp, etc.)
- User documents (imported or generated)
- User database file (`user.db`) entry

Import button supports:

- `.txt`
- `.geojson`
- `.pdf` (except Linux)
- `user.db`

Document behavior:

- Text: in-app text reader
- PDF: in-app PDF viewer (if supported)
- GeoJSON: parsed into map shapes (visible when GeoJSON layer is on)
- Images: zoomable preview
- Share button available where supported
- Swipe delete for user files

### 9.3 Aircraft

Open: **Menu → Aircraft**

Create/manage aircraft profiles with fields used by planning/filing/identification:

- tail, type, colors/markings, PIC info, home base, mode-S code,
- cruise TAS, fuel endurance/burn, sink rate,
- wake category, equipment, surveillance, other ICAO info.

Save and select active aircraft from dropdown.

### 9.4 Check Lists

Open: **Menu → Check Lists**

- Import checklist from `.txt` (first line title, following lines steps)
- Tick steps with checkbox list
- Background turns green when all steps complete
- Select checklist from dropdown
- Swipe delete to remove checklist

### 9.5 W&B (Weight and Balance)

Open: **Menu → W&B**

Functions:

- Build/edit envelope chart bounds and polygon
- Tap chart in edit mode to add/remove envelope vertices
- Enter line-item weight/arm rows
- Auto-calculate moments and total CG
- CG point color:
  - green = inside envelope
  - red = outside envelope

Use **Edit/Save** to modify and persist.

### 9.6 Log Book

Open: **Menu → Log Book**

Features:

- Add/edit/delete full logbook entries
- Total hours summary
- Import CSV / Export CSV
- “Details” dashboard with filters and charts

Dashboard filters include:

- Year
- Tail number
- Aircraft type
- Remarks tags (check ride / IPC / flight review / favorite)

Charts include hours by year, tail, aircraft type, hour categories, and procedure counts.

### 9.7 IO (Bluetooth) — Android

Open: **Menu → IO**

Functions:

- Device discovery
- Pair / unpair
- Connect / disconnect bonded devices
- Shows RSSI and connection state

Connected stream feeds external data input into app parser.
Also used by Plan Transfer (Garmin Connext).

### 9.8 Donate

Open: **Menu → Donate** (when available)

- Displays donation URL for browser use.

---

## 10) Notes Screen

### 10.1 How to access

On MAP tab, tap the notes/pen icon in bottom-right controls.

### 10.2 Features

- Freehand drawing with color choices
- Eraser mode
- Undo/Redo
- Clear canvas
- Save snapshot to Documents as `notes_<timestamp>.jpg`
- Current sketch autosaves on exit and reloads next time

---

## 11) Pro Services (iOS/Android)

### 11.1 Access

From MAP top-right account icon, or by routed requests from some features.

### 11.2 Login and subscription flow

- Sign in/register with email auth
- Paywall handled through RevenueCat entitlement (`Pro`)

### 11.3 Flight Intelligence (AI)

Screen title: **Flight Intelligence**

Capabilities:

- Ask free-form aviation/trip questions (internet required)
- Optional context toggles:
  - recent logbook entries
  - selected aircraft
  - current flight plan + winds
- Query/answer history drawer:
  - choose prior query
  - show prior answer
  - delete history item

### 11.4 Backup/Sync

Screen title: **Backup/Sync**

Cloud operations for `user.db`:

- **Backup**: upload local database to cloud storage
- **Restore**: download cloud backup over local database
- both actions show confirmation warnings and progress/status

---

## 12) Warnings and Troubleshooting Drawer

When warning state is active, a red alert icon appears on MAP.
Tap it to open issues drawer.

Possible issue items:

- GPS permission denied (opens app settings)
- GPS disabled (opens location settings)
- No GPS lock
- Critical data/charts missing (shortcut to Download)
- Data expired (shortcut to Download)
- runtime exception notices

---

## 13) Data Lifecycle and Auto-Update Behavior

- Weather downloads refresh periodically (10-minute cycle in storage timer).
- GPS source auto-switches:
  - prefers external stream when available
  - falls back to internal GPS after timeout.
- Flight status tracks taxi/airborne transitions and accumulates flight time.
- External autopilot/NMEA sentence output is generated continuously while app is running and IO connection exists.

---

## 14) Quick Feature Path Index

- Download charts/data: `MAP → Menu → Download`
- Read weather docs / import files: `MAP → Menu → Documents`
- Build or modify plan: `PLAN tab`
- File FAA plan: `PLAN → Actions → Brief & File`
- Manage filed plans: `PLAN → Actions → Manage`
- Send plan to Garmin: `PLAN → Actions → Transfer` (Android)
- Destination details: long-press on map or tap FIND result
- Show plates for airport: destination popup `Plates` or `PLATE tab`
- Configure aircraft: `MAP → Menu → Aircraft`
- Checklist operations: `MAP → Menu → Check Lists`
- Weight and balance: `MAP → Menu → W&B`
- Logbook + dashboard: `MAP → Menu → Log Book`
- Bluetooth pairing/connection: `MAP → Menu → IO` (Android)
- Notes/drawing: `MAP → Notes icon`
- Pro AI: `MAP top-right account icon → Flight Intelligence`
- Cloud backup/restore: `MAP top-right account icon → Backup/Sync`

---

## 15) Step-by-Step Use Cases (Common Scenarios)

### UC-01: Connect an external ADS-B/GPS receiver over Wi-Fi UDP

Best when your receiver broadcasts GDL90/NMEA over local network.

1. Power on your ADS-B/GPS receiver.
2. Connect your tablet/phone/computer to the receiver's Wi-Fi network (or same LAN).
3. Open AvareX and go to `MAP`.
4. Wait for incoming data on supported UDP ports: `4000`, `43211`, or `49002` (automatic listener).
5. Turn on useful map layers:
   - `Traffic`
   - `Weather`
   - `Radar` (internet radar)
6. Verify data:
   - ownship updates smoothly,
   - traffic symbols appear (if in range),
   - weather products populate.
7. If needed, open warning drawer from red icon and resolve GPS/data warnings.

### UC-02: Connect an external ADS-B/GPS receiver over Bluetooth (Android)

1. Open `MAP → Menu → IO`.
2. Tap refresh/replay icon to discover devices.
3. Select your receiver from list.
4. Pair (if needed), then tap **Connect**.
5. Confirm status line shows connected device.
6. Return to map and enable `Traffic` / `Weather` layers as needed.
7. To disconnect: `IO → Disconnect`.

### UC-03: Rubber-band a route directly on the map

Use this to adjust waypoints graphically.

1. Ensure your route has waypoints (`PLAN` tab or destination popup `+Plan`).
2. Go to `MAP`.
3. Tap the **rubber banding** icon (decision arrow) to enable it (icon turns active/red).
4. Long-press a waypoint marker or label and drag to a new position.
5. Release to snap/update from database lookup and rebuild route geometry.
6. Turn rubber banding off when done to avoid accidental edits.

### UC-04: Build a flight plan from scratch (quick VFR workflow)

1. Open `PLAN` tab.
2. Add waypoints using either:
   - `FIND` tab → tap item → `+Plan`, or
   - `MAP` long-press destination popup → `+Plan`.
3. Reorder legs by drag in `PLAN`.
4. Tap a leg to make it current.
5. Set `ASpd`, `GPH`, and `Alt` at bottom of `PLAN`.
6. Open nav-log (fuel icon) to review:
   - leg calculations,
   - winds-aloft field,
   - terrain profile.
7. Save the route: `PLAN → Actions → Load & Save → Save`.

### UC-05: Create an IFR route automatically

1. Open `PLAN → Actions → Create`.
2. In Route field:
   - enter route text and use **Create As Entered**, or
   - enter `DEPART DEST` and use **Create IFR Preferred Route**, or
   - use **Show IFR ATC Routes** to view recent ATC route options.
3. When route is loaded, return to `PLAN` to review/reorder waypoints.

### UC-06: File a flight plan with the FAA

Prereq: set your 1800wxbrief-compatible email in onboarding.

1. Build/verify your route in `PLAN`.
2. Open `PLAN → Actions → Brief & File`.
3. Fill required fields (aircraft ID/type, rule, departure, destination, route, times, fuel, POB, etc.).
4. Use quick-fill buttons:
   - planned departure/destination/route,
   - stored aircraft templates.
5. Tap:
   - **Get Email Brief** for briefing email, and/or
   - **Send to FAA** to file.
6. Check status indicator/message for success/errors.

### UC-07: Activate, close, or cancel an FAA flight plan

1. Open `PLAN → Actions → Manage`.
2. Find your plan in the list.
3. Use action by state:
   - `PROPOSED`: **Depart** (choose time) to activate,
   - `ACTIVE`: **Close** after landing,
   - non-active: **Cancel** if no longer needed.

### UC-08: Quickly divert to a nearby airport

1. On `MAP`, long-press near destination area.
2. In popup, review nearby list and tap a candidate airport.
3. Tap `→D` to set Direct-To and center map.
4. Optional:
   - tap `Plates` for immediate airport diagrams/procedures,
   - add to full route with `+Plan`.

### UC-09: Use plates with procedure profile and add procedure to plan

1. Open `PLATE` tab.
2. Select airport (bottom-right selector).
3. Select desired plate (bottom-left selector).
4. Use procedure menu (plus icon):
   - choose procedure to show profile,
   - use `+Plan` to append procedure to route.
5. Keep instruments visible on plate using top-right show/hide toggle.

### UC-10: Save your flown track and retrieve it from Documents

1. In `MAP`, keep `Tracks` layer on during flight.
2. When done, set `Tracks` layer opacity to `0` in Layers menu.
3. App saves track automatically as KML in Documents.
4. Open `MAP → Menu → Documents → User Docs` to access/share file.

### UC-11: Import a GeoJSON overlay and display it on map

1. Open `MAP → Menu → Documents`.
2. Tap **Import** and select a `.geojson` file.
3. Open `MAP` and set `GeoJSON` layer opacity > 0.
4. Imported polygons/markers now draw on the map.

### UC-12: Transfer your plan to a Garmin device (Android)

1. Build your route with at least 2 waypoints.
2. Connect Garmin device in `MAP → Menu → IO`.
3. Open `PLAN → Actions → Transfer`.
4. Confirm connected device label.
5. Tap **Send to Garmin**.
6. Wait for success toast/status.

### UC-13: Back up and restore app data (Pro)

1. Open Pro Services from account icon on map.
2. Sign in and pass entitlement/paywall if required.
3. Open `Backup/Sync`.
4. Use:
   - **Backup** to upload local `user.db`,
   - **Restore** to overwrite local data from cloud copy.
5. Confirm prompts carefully (both operations overwrite existing data).

### UC-14: Get flight help from community resources

1. In onboarding or browser, open Apps4Av forum:
   - `https://groups.google.com/g/apps4av-forum`
2. Search existing threads for similar workflows/devices.
3. Post issue details:
   - platform/device,
   - receiver type,
   - what screen/action failed,
   - any warning drawer messages.

---

## 16) Resources and Support

- Apps4Av Forum (Google Groups):  
  `https://groups.google.com/g/apps4av-forum`
- Store links and platform download details: see `README.md`.
- For in-app issues, always check the MAP warning drawer first (red icon).

---

## 17) Forum-Derived FAQ and Scenarios (Google Groups)

The following FAQs are derived from recent threads in the Apps4Av forum and mapped to the current AvareX workflows.

### FAQ-01: How do I connect an external ADS-B / GPS receiver?

- For Wi-Fi receivers: connect the device to receiver network and AvareX auto-listens on UDP `4000`, `43211`, `49002`.
- For Bluetooth receivers (Android): `Menu -> IO`, pair/connect, then return to map.
- Source threads:
  - GPS source discussion:  
    `https://groups.google.com/g/apps4av-forum/c/e0ujCJQX1s8`
  - In-flight ADS-B issues:  
    `https://groups.google.com/g/apps4av-forum/c/ZP2E9l35Dk8`
  - Android IO functionality:  
    `https://groups.google.com/g/apps4av-forum/c/WI-BcDK7rT0`

### FAQ-02: How do I transfer a plan to Garmin?

- Build a route with at least 2 waypoints.
- On Android, connect device in `Menu -> IO`.
- Open `PLAN -> Actions -> Transfer`, then **Send to Garmin**.
- Source threads:
  - Testing Garmin transfer:  
    `https://groups.google.com/g/apps4av-forum/c/k958J5yLyR4`
  - Importing/transfer conversation:  
    `https://groups.google.com/g/apps4av-forum/c/acmWm72qITY`

### FAQ-03: Where do I enable new wind/ceiling map features?

- `MAP -> Layers`:
  - enable **Wind Vectors** and/or **Ceiling**
  - use left altitude slider to change displayed altitude context.
- Source threads:
  - New features v83/v84:  
    `https://groups.google.com/g/apps4av-forum/c/qac4-Bb-gVE`  
    `https://groups.google.com/g/apps4av-forum/c/Xvhc9yeE42A`

### FAQ-04: My track logs are empty. How do I save valid KML logs?

- Keep `Tracks` layer ON during flight.
- After flight, turn `Tracks` layer OFF (saves KML to Documents and clears active track buffer).
- Open `Documents -> User Docs` and verify non-empty KML before sharing.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/goPy8KQpfik`

### FAQ-05: Where are FBO/business details?

- On `PLATE` screen, when an airport diagram is active and business data is available, use the right-side business selector (`...` style control).
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/oMOR-gaIqis`

### FAQ-06: What are the blue rings on map?

- In the `Circles` layer:
  - black rings: fixed 2/5/10 NM reference rings
  - blue ring: speed-based 1-minute range ring
  - glide circle: aircraft sink-rate based glide estimate
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/VJ0S3ejWPC8`

### FAQ-07: My waypoints appear in wrong order. Can I reorder quickly?

- Yes. In `PLAN`, drag rows to reorder legs.
- You can also set current leg by tapping a waypoint row.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/T-m4BWZynMg`

### FAQ-08: How do I enter an ATC reroute quickly?

- Open `PLAN -> Actions -> Create`.
- Use **Create As Entered** and paste/type reroute string (space-separated waypoints/airways).
- Then review/reorder in PLAN list if needed.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/ukaXEEhpvS0`

### FAQ-09: Download/cycle issues - what to try first?

- In `Download` screen:
  - try **This Cycle** vs **Next Cycle**
  - try **Main Server** vs **Backup Server**
  - keep download screen open until completion (exiting can abort incomplete downloads).
- Source threads:
  - cycle download issue:  
    `https://groups.google.com/g/apps4av-forum/c/LS_VaqKEJxw`
  - background download request:  
    `https://groups.google.com/g/apps4av-forum/c/XcoQzwpCxlw`

### FAQ-10: FAA IFR preferred route tools not working - what now?

- Ensure app is updated to latest release and internet is available.
- Confirm your 1800wxbrief-compatible email is configured.
- Retry via `PLAN -> Actions -> Create` and `Brief & File`.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/0wHqcJT-WiY`

### FAQ-11: Is Flight Intelligence (AI) available on desktop?

- Current Pro AI workflows are targeted for iOS/Android in this codebase.
- Access from map account icon -> Pro Services -> Flight Intelligence.
- Source threads:
  - AI feature thread:  
    `https://groups.google.com/g/apps4av-forum/c/wWZUn6TNG1w`
  - desktop/pro services request:  
    `https://groups.google.com/g/apps4av-forum/c/XcoQzwpCxlw`

### FAQ-12: Can I use AvareX with X-Plane/simulator feeds?

- AvareX accepts external NMEA/GDL90-like streams via UDP listener ports.
- For simulator setups, configure simulator/network output accordingly.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/QOfnQ-pkT0w`

---

