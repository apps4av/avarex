# AvareX User Manual

This manual documents all features in the current AvareX app, including:

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
  - Chart/database downloads
  - Weather/doc products
  - Flight Intelligence (AI)
  - FAA plan services / cloud backup
- GPS can come from:
  - Internal device GPS
  - External ADS-B / GPS streams over **UDP ports 4000, 43211, 49002**
  - External Bluetooth stream (Android IO screen)

### 1.3 First-run onboarding checklist

On first run, complete onboarding pages:

1. **Sign Terms of Use** (required to continue).
2. Select **Day/Night theme**.
3. Select units:
   - Maritime (NM/knots/feet)
   - Imperial (SM/MPH/feet)
4. Confirm GPS permissions/settings.
5. Open **Download** and get at least **DatabasesX** (required for core nav data).
6. Optional: register your 1800wxbrief.com email for FAA flight-plan workflows.

You can reopen onboarding later from the drawer header icon.

---

## 2) Platform Feature Availability

| Feature | Availability |
|---|---|
| Core app (Map/Plate/Plan/Find, downloads, documents, aircraft, checklist, W&B, logbook) | All supported platforms |
| Track Viewer with 2D/3D views (KML files) | All supported platforms |
| Vector map layer with airspace | All supported platforms |
| CAP Grid layer | All supported platforms |
| Bluetooth IO screen | **Android only** |
| Plan Transfer via NMEA 0183 | **Android only** (through Bluetooth IO) |
| Pro Services (Flight Intelligence + Backup/Sync) | **iOS and Android only** |
| PDF viewing in Documents/Help | Not available on Linux |
| File sharing from Documents/Logbook export | Not available on Linux |
| Donate screen | Not available on iOS/macOS |

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
- Donate (not iOS/macOS)
- Help (opens User Manual PDF; not available on Linux)

---

## 4) MAP Tab (Primary Flight Display + Map Tools)

### 4.1 How to access

Tap bottom tab **MAP**.

### 4.2 Core interactions

- Pan/zoom map
- Track-up or North-up orientation toggle
- Long-press behavior:
  - If ruler mode OFF: opens destination popup near pressed location
  - If ruler mode ON: drops ruler points for distance/bearing measurement
- Single tap dismisses pop-up toasts

### 4.3 Map controls (buttons and menus)

#### Top-right
- **Pro icon** (iOS/Android): opens Pro Services login/paywall flow.
- **Red warning icon** (if active): opens troubleshooting drawer.

#### Bottom center
- **Center** button:
  - Tap: recenter on ownship (current zoom)
  - Long press: recenter and zoom to chart max zoom

#### Bottom-left
- **Menu** button: opens drawer list (Download, Documents, etc.)

#### Bottom-right control row (scrollable)
- **Mute** (volume icon): toggle audible alerts (traffic, GPWS) on/off.
- **Ruler** (compass icon): toggle measure mode; long-press map to add points. Red when active.
- **North-up / Track-up toggle**: switches orientation mode.
- **Rubber banding toggle**: enables dragging route waypoints directly on map. Red when active.
- **Notes icon**: opens handwriting Notes screen.
- **Chart type popup**: selects chart source type.
- **Layers popup**: per-layer on/off via opacity slider.

#### Traffic-only controls (show when Traffic layer > 0)
- **Traffic puck size** cycles: `S`, `M`, `L`
  - S: 20 aircraft, 3000 ft, 10 NM
  - M: 200 aircraft, 6000 ft, 50 NM
  - L: 1000 aircraft, 30000 ft, 500 NM

#### Altitude slider (right side)
- Appears when **Ceiling** or **Wind Vectors** layer is on.
- Range: 0 to 30,000 ft (1,000 ft increments).
- Adjusts planning altitude used by those overlays.

### 4.4 Map chart types

Selectable map chart types with max zoom levels:

| Chart Type | Max Zoom | Description |
|------------|----------|-------------|
| Sectional | 10 | VFR sectional charts |
| TAC | 11 | Terminal Area Charts (metro areas) |
| IFR Low | 10 | IFR Enroute Low Altitude charts |
| IFR High | 9 | IFR Enroute High Altitude charts |
| IFR Area | 11 | IFR Area charts |
| Helicopter | 12 | Helicopter route charts |
| Flyway | 11 | VFR Flyway planning charts |

### 4.5 Map layers and what they do

Layer list from settings (with per-layer opacity 0-100%):

| Layer | Description |
|-------|-------------|
| **Nav** | Route lines (cyan=passed, purple=current, gray=next), runway depiction, waypoint markers/labels, ownship symbol, wind barb, north indicator. |
| **Circles** | Range rings (10/5/2 NM black rings), speed ring (blue, 1-minute travel distance), glide circle (purple, power-off glide range) + labels. |
| **Chart** | Downloaded FAA chart tiles (offline chart base). |
| **Vector Map** | NASR vector tiles from MBTiles files, with Class B/C/D airspace and SUA (MOA, Restricted, Warning, Alert, Prohibited, NSA) rendered with standard aviation colors. |
| **CAP Grid** | Civil Air Patrol grid overlay with grid identifiers (e.g., BOS42, SEA123). Only visible at zoom level 9+. |
| **Topo** | USGS topo online base map (max zoom 16). |
| **Elevation** | Downloaded elevation tiles with color-coded terrain. |
| **Weather** | METAR/TAF/PIREP/AIRMET/SIGMET symbols + ADS-B weather overlays (NEXRAD from GDL90/FIS-B). Color-coded by flight category (green=VFR, blue=MVFR, red=IFR, purple=LIFR). |
| **Radar** | Internet radar animation tiles from Iowa State Mesonet (loops through 5 time frames: -40m, -30m, -20m, -10m, now, cycling every 250ms). |
| **TFR** | Temporary flight restriction shapes/markers with time validity. Red=active, orange=future. |
| **Wind Vectors** | Animated wind particle field overlay at selected altitude (from Winds Aloft data). |
| **Ceiling** | Black overlay showing areas where METAR ceiling is below your selected altitude. |
| **Plate** | Georeferenced plate overlay on map (when loaded). |
| **Traffic** | Traffic symbols with relative orientation, altitude, vertical trend, callsign; audible alerts integration (cyan=proximate, orange=advisory, red=resolution). |
| **Obstacles** | Obstacle markers (red squares) in your vicinity. |
| **Tape** | Distance tape labels from ownship upward in NM. |
| **GeoJSON** | Imported user GeoJSON polygons/markers. |
| **PFD** | Inset Primary Flight Display panel (artificial horizon, speed/altitude tapes, VSI, compass, CDI/VDI, AOA indicator, turn coordinator). Requires AHRS data. |
| **Tracks** | Ownship breadcrumb/polyline track recording (green line). |

Notes:

- Turning **Tracks** layer OFF saves a KML track file into Documents/tracks and clears active track recording.
- **PFD** requires AHRS data from GDL90-compatible devices to show attitude.

### 4.6 Instrument strip (top-left)

Reorderable instrument tiles include:

| Tile | Description | Tap Action |
|------|-------------|------------|
| **GS** | Ground speed (knots/mph) | — |
| **ALT** | GPS altitude (feet) | — |
| **MT** | Magnetic track (degrees) | — |
| **PRV** | Previous waypoint identifier | Jump to previous waypoint |
| **NXT** | Next waypoint identifier | Jump to next waypoint |
| **DIS** | Distance to next waypoint (NM/mi) | — |
| **BRG** | Bearing to next waypoint (magnetic) | — |
| **GEL** | Ground elevation (requires Elevation charts) | — |
| **ETA** | Estimated time of arrival (HH:MM) | — |
| **ETE** | Estimated time en-route (HH:MM) | — |
| **VSR** | VSI required to arrive 1000ft above destination | — |
| **UPT** | Up timer (count up, green when running) | Start/stop timer |
| **DNT** | Down timer (count down from 30min, red when expired) | Start/stop timer |
| **UTC** | Current UTC time (HH:MM) | — |
| **SRC** | GPS source mode. Shows `Internal`, `External`, `Internal-A`, or `External-A` (A=Auto mode) | Tap to cycle modes: Auto, Internal, External. Green=Internal, Blue=External |
| **FLT** | Total flight time in hours | Reset timer |

Interactions:

- Dropdown arrow: expand/contract tile sizes
- Drag tiles to rearrange order
- `?` icon: show help with tile descriptions

### 4.7 GPWS (Ground Proximity Warning System)

- Monitors terrain ahead in direction of flight
- Predicts collisions within 3-minute lookahead
- Audible "PULL UP" alerts
- Requires: 30+ knot ground speed, Elevation data downloaded

### 4.8 Weather marker interactions

- **METAR tap**: Shows full METAR text with flight category icon
- **TAF tap**: Shows TAF forecast
- **PIREP tap**: Shows pilot report
- **AIRMET/SIGMET tap**: Shows advisory text. **Long-press**: toggles shape visibility on map
- **TFR tap**: Shows TFR details (altitudes, times)

### 4.9 Ruler/measurement tool

- Activate via compass icon (turns red when active)
- Long-press map to add measurement points
- Shows distance (NM) and bearing (degrees) between points
- Multiple segments supported

### 4.10 Rubber banding

- Activate via toggle button (turns red when active)
- Long-press and drag waypoint icons to reposition
- On release, snaps to nearest navaid/fix from database
- Must be explicitly enabled to prevent accidental edits

---

## 5) Destination Popup (Map Long-Press or Find Tap)

### 5.1 How to access

- Long press on map (when ruler mode is off), or
- Tap an item in FIND list

### 5.2 Top action buttons

- **→D**: set Direct-To destination, center map there, return to map
- **+Plan**: insert destination into current plan at the current waypoint position
- **↓Plan**: append destination to the end of the plan
- **Plates** (airport only): jump to PLATE tab at that airport

### 5.3 Information pages (shown when data exists)

Possible tabs:

- **Main**: destination summary (airport info, runway diagram, or VOR/navaid info with nearby VORs)
- **AD**: airport diagram/runway depiction (interactive viewer with zoom)
- **METAR**: METAR + TAF text with flight category color indicator
- **NOTAM**: fetched NOTAM list (downloaded async)
- **SUA**: special-use airspace data for the area
- **Wind**: nearest winds-aloft station data at multiple altitudes
- **ST**: sounding chart/image for the area (Skew-T diagram)
- **Business**: nearby business/FBO list (with AI **Details** button when Pro enabled)

If nearby alternatives exist, a horizontal "Nearby" selector appears.

---

## 6) PLATE Tab

### 6.1 How to access

- Bottom tab **PLATE**, or
- From destination popup using **Plates**

### 6.2 What it does

- Displays downloaded plates/diagrams/CSUP
- Draws ownship and heading on georeferenced plates
- Can overlay selected business/FBO marker on airport diagrams
- Supports zoom/pan via InteractiveViewer (up to 8x)

### 6.3 Controls

- **Airport selector** (bottom-right): choose airport from recent airports list
- **Plate selector** (bottom-left): choose plate within airport (color-coded by type)
- **Procedure menu** (plus icon near bottom-right):
  - Show procedure profile
  - `+Plan` adds procedure waypoint sequence to plan
- **Instrument strip show/hide** toggle (top-right arrow icon)
- **Profile close (X)** closes procedure profile card

### 6.4 Plate type color coding

| Color | Plate Type |
|-------|------------|
| Green | Airport Diagram (APD) |
| Blue | CSUP |
| Pink | Departure Procedure (DP) |
| Purple | Instrument Approach (IAP) |
| Cyan | STAR |
| Brown | Minimums (MIN) |
| Red | Hot Spots (HOT), Land and Hold Short (LAH) |

### 6.5 Terrain caution overlay on plates

When map **Elevation** layer has opacity > 0, plate rendering can include colored terrain risk cells:

- **Yellow**: terrain within 500-1000 ft below aircraft
- **Red**: terrain within 500 ft or above aircraft

### 6.6 Business/FBO selector

On airport diagrams, when business data is available, a right-side selector (three dots icon) allows you to:
- Select a business/FBO
- See its location marked on the airport diagram
- Name label appears next to the marker

### 6.7 Automatic behavior on landing

Flight-state logic can auto-switch plate context to nearest airport diagram after landing (if available).

---

## 7) PLAN Tab

### 7.1 How to access

Tap bottom tab **PLAN**.

### 7.2 Main plan editor

- Reorderable waypoint list (long-press and drag to reorder)
- Swipe row right-to-left to delete waypoint
- Tap row to set current waypoint (highlighted in purple with "ACTIVE" badge)
- **Long-press** row to insert a waypoint after that position (opens FIND tab; next selection inserts after the long-pressed waypoint)
- Header row shows plan-wide calculated totals (Distance, Ground Speed, Course, Time, Fuel)
- Airways and procedures show as expandable items with nested waypoints

Bottom controls:

- **Actions** button opens Plan Actions screen
- **ASpd** field: true airspeed used in calculations (knots)
- **GPH** field: fuel burn (gallons per hour)
- **Alt** field: plan altitude (feet, default 3000)
- **Forecast horizon** selector: 06H / 12H / 24H (winds aloft forecast period)
- **Analytics icon** (chart): opens full-screen Navigation Log

### 7.3 Navigation Log dialog

Includes:

- **Per-leg log grid** with columns: FM (from), TO (to), AL (altitude), TC (true course), VR (variation), MC (magnetic course), WD (wind direction@speed), CA (wind correction angle), MH (magnetic heading), DT (distance), GS (ground speed), TM (time), FC (fuel consumption)
  - Grid is zoomable/pannable; **double-tap** to reset zoom
- **Winds & Terrain En Route diagram**: combined visualization showing wind components and terrain profile:
  - **Wind heat map**: color-coded cells at altitudes 0-18000 ft along route (green = tailwind, red = headwind, darker = lighter winds, brighter = stronger winds up to 50 kt scale)
  - **Plan altitude line**: cyan horizontal line showing your planned altitude
  - **Terrain profile overlay**: terrain elevation curve with color coding (green = safe below plan altitude, red = at or above plan altitude)
  - **Waypoint markers**: cyan tick marks at the bottom showing waypoint positions along the route
  - **Interactive tap**: tap anywhere on the diagram to display a tooltip with:
    - Nearest waypoint (if within 5% of route position)
    - Altitude at tap position (snaps to altitude bands: 0, 3000, 6000, 9000, 12000, 18000 ft)
    - Terrain elevation at that point
    - Course direction
    - Wind direction and speed
    - Tailwind/headwind component in knots
- **Copy plan to clipboard** button (app bar)

### 7.4 Plan Actions screen

Sub-pages (accessed via bottom navigation buttons):

#### A) Load & Save
- Save current plan by name
- Load saved plan
- Load reversed (loads plan in reverse order)
- Delete saved plan
- Tap any plan to load immediately

#### B) Create
- **Create As Entered**: parse typed route string (space-separated waypoints/airways, e.g., `KBOS V123 KHPN`)
- **Create IFR Preferred Route**: build from rfinder.asalink.net API (enter `DEPART DEST`)
- **Show IFR ATC Routes**: show recent ATC routes between departure/destination from 1800wxbrief with last departure times

#### C) Brief & File (FAA)
- Detailed ICAO form fields:
  - Aircraft ID, Type, Flight Rule (VFR/IFR), Flight Type, Number of Aircraft
  - Wake Turbulence (LIGHT/MEDIUM/HEAVY)
  - Aircraft Equipment, Surveillance Equipment
  - Departure, Departure Date/Time Zulu
  - Cruising Speed, Altitude, Route
  - Destination, Total Elapsed Time
  - Alternate Airports (1 & 2)
  - Fuel Endurance, People On Board
  - Aircraft Color, Remarks
  - Pilot in Command, Pilot Information
- Quick-fill buttons from current plan and stored aircraft
- Buttons:
  - **Get Email Brief**: sends briefing request to 1800wxbrief (50nm corridor)
  - **Send to FAA**: files flight plan via LMFS API
- Status indicator (check mark=success, info icon with tooltip=error)

Requires configured 1800wxbrief-compatible account email.

#### D) Manage (FAA)
- Retrieve filed plans
- State-aware actions with color coding:
  - **PROPOSED** (blue): **Cancel** or **Depart** (activate with chosen time - opens time picker with sunrise/sunset)
  - **ACTIVE** (green): **Close**
  - **CLOSED** (grey): view only

#### E) Transfer (Android only)
- Sends flight plan via standard NMEA 0183 RTE/WPL sentences over Bluetooth
- Requires Bluetooth connection in IO screen
- Minimum 2 waypoints required
- Shows connection status and connected device label
- **Open Bluetooth** button navigates to IO screen
- **Send to Garmin** button transmits the plan

**Compatible devices:** Older handheld GPS units and devices that accept NMEA 0183 waypoint/route input (e.g., some autopilot systems, marine chartplotters, GPSMAP handhelds).

**Not compatible:** Modern Garmin panel-mount avionics (G3X Touch, GTN 650/750, GNS 430W/530W) use Garmin's proprietary Connext protocol, which is only available to Garmin Pilot and ForeFlight. These devices will show "Connected" over Bluetooth but will not import flight plans sent via NMEA RTE/WPL.

### 7.5 Route building details

**Waypoint types supported:**
| Type | Description |
|------|-------------|
| GPS | User-entered lat/lon coordinates |
| Airport | Airport from database |
| Navaid | VOR/NDB |
| Fix | Named fixes/intersections |
| Airway | Victor (V) and Jet (J) routes |
| Procedure | SID/STAR/Approach (format: `AIRPORT.PROCEDURE.TRANSITION`) |

**Airway processing:**
- Automatically finds entry and exit points when airway is between two waypoints
- Max segment length: 500nm (separates AK/HI from lower 48)
- Populates actual fix names asynchronously

### 7.6 Automatic waypoint passage

When within 2nm of a waypoint and moving away from it, the plan automatically advances to the next waypoint.

---

## 8) FIND Tab

### 8.1 How to access

Tap bottom tab **FIND**.

### 8.2 What it does

- Search destinations by text (airports, navaids, fixes, GPS coordinates)
- Browse:
  - Recent (previously viewed destinations)
  - Nearest (nearest airports)
  - Nearest 2K (runway >= 2000 ft)
  - Nearest 4K (runway >= 4000 ft)

### 8.3 Row actions

- Tap row: opens destination popup/details
- Right-side bearing@distance button: centers map on item and switches to MAP
- Swipe right-to-left to delete recent entry
- For GPS-type recents, tap edit icon to modify custom facility name

---

## 9) Drawer Features

### 9.1 Download

Open: **Menu → Download**

Purpose:

- Install/update/delete downloadable data sets by chart category and region
- Monitor progress with per-item progress ring and stop button

**Status Summary Card:**
- Shows counts of Current, Expired, To Download, and To Delete items

**State Indicators:**
- Green = Current (up-to-date)
- Orange = Expired (needs update)
- Gray = Absent (not downloaded)

Controls:

- Tap chart item to queue for download/update/delete
- **Download** button processes all queued items
- **Update** button automatically updates all expired charts
- Toggle **This Cycle / Next Cycle**
- Toggle **Main Server / Backup Server**
- Info map icon shows regional coverage image

Major download categories include:

- **Databases**: DatabasesX (required for core nav data), Business/FBO
- **VFR Charts**: Sectional, TAC, Flyway, Helicopter
- **IFR Charts**: IFR Low, IFR High, IFR Area
- **Procedures**: Plates, CSUP
- **Terrain**: Elevation

Regional coverage (9 regions): Northeast, North Central, Northwest, Southeast, South Central, Southwest, East Central, Alaska, Pacific

### 9.2 Documents

Open: **Menu → Documents**

Includes:

- Built-in weather/prog chart products (fetched from aviationweather.gov):
  - WPC Surface Analysis & Prognostic charts (6/12/18/24/30/36/48/60/72HR)
  - SigWx Low Level & Mid Level charts (00/06/12/18HR)
  - Radar & SIGMETs
  - AIRMET Tango (turbulence), Sierra (mountains/IFR), Zulu (icing) - 00/03/06/09/12HR
  - Surface Forecast charts (03-18HR)
  - Clouds Forecast charts (03-18HR)
  - Winds/Temperature at altitudes 5000-30000ft (06/12HR)
- User documents (imported or generated)
- User database file (`user.db`) entry
- Subfolders for organization:
  - `tracks/` — saved flight tracks (KML files)
  - `notes/` — saved notes screenshots

**Folder management:**

- **Create folder**: tap folder icon in app bar to create a new subfolder
- **Delete folder**: use delete icon below folder to remove folder and contents
- **Move files**: use move icon on user files to relocate to a folder or back to root
- **Export folder**: use share icon below folder to export all folder contents (not Linux)
- **Navigate**: tap folder to enter, use back arrow to go up

**Filter dropdown:** Filter by document category (All Documents, User Docs, WPC, SigWx, etc.)

Import button supports:

- `.txt` — text files
- `.geojson` — GeoJSON geographic data
- `.kml` — KML track files
- `.pdf` (except Linux)
- `user.db` — user database backup

Document behavior:

- Text: in-app text reader
- PDF: in-app PDF viewer (if supported)
- GeoJSON: parsed into map shapes (visible when GeoJSON layer is on)
- KML: opens Track Viewer with 2D map, altitude profile, and 3D terrain view
- Images: zoomable preview
- Share button available where supported (not Linux)
- Swipe delete for user files (preserves User Data entry)

#### Track Viewer (KML files)

When you tap a KML file in Documents, the Track Viewer opens with three view modes (toggle via app bar icons):

- **2D Map** (map icon): displays the track on a USGS topo background with:
  - Flight track polyline (blue)
  - Start marker (green takeoff icon)
  - End marker (red landing icon)
  - **Log Flight** FAB button to create logbook entry

- **Altitude Profile** (chart icon): shows altitude vs. distance graph:
  - Line chart of altitude (ft) over distance (NM)
  - Min/max altitude display
  - Total distance in nautical miles
  - Shaded area under curve

- **3D View** (AR icon): interactive 3D visualization:
  - Terrain grid with elevation data (fetched for 20nm buffer)
  - Topo map texture projected onto terrain mesh
  - Flight path with color gradient (green→yellow→orange→red)
  - Drop lines connecting track to terrain surface
  - Vertical scale with altitude tick marks (1000ft increments)
  - Drag to pan, two-finger rotate, pinch to zoom
  - Reset View button

**Auto Logbook Entry Creation (Log Flight button):**
- Uses nearest airports for route (takeoff and landing)
- Calculates flight time from track timestamps or from distance/cruise TAS
- Creates entry with aircraft make/model and tail from selected aircraft profile

### 9.3 Aircraft

Open: **Menu → Aircraft**

Create/manage aircraft profiles with fields used by planning/filing/identification:

**Identification:**
- **Tail Number**: Aircraft registration (e.g., N172EF)
- **Type**: Aircraft type (e.g., C172)
- **Color & Markings**: FAA color codes (A=Amber, B=Blue, BK=Black, R=Red, W=White, etc.)
- **Mode S Code**: Hex transponder code from FAA registry

**Pilot Information:**
- **PIC**: Pilot name
- **PIC Information**: Contact info (phone, etc.)
- **Home Base**: Airport code (e.g., KBVY)

**Performance:**
- **Cruise Speed**: True airspeed in knots
- **Fuel Endurance**: In decimal hours (5.5 = 5h30m)
- **Fuel Burn Rate**: Gallons per hour
- **Sink Rate**: Feet per minute for glide calculations
- **Wake Turbulence**: LIGHT, MEDIUM, or HEAVY

**Equipment:**
- **Equipment codes**: D, G, I, L, O, R, S, T, V, W
- **Surveillance codes**: N, A, C, S, B1/B2, U1/U2
- **Other Information**: STS/, PBN/, NAV/, COM/, DAT/, SUR/, DEP/, DEST/, etc.

**Map Icon Selection** (dropdown in app bar):
- Choose aircraft icon for map display: plane, helicopter, or canard
- Visual icon previews in dropdown

Save and select active aircraft from dropdown. Swipe left to delete aircraft.

### 9.4 Check Lists

Open: **Menu → Check Lists**

- **Progress bar**: shows completion percentage with completed/total count
- **Checkbox items**: tap to check off steps
- **Visual feedback**:
  - Checked items: green background, strikethrough text
  - All complete: green progress bar and background
- **Reset button**: reset all items to unchecked
- **Multiple checklists**: dropdown to switch between saved checklists
- Import checklist from `.txt` (first line is title, following lines are steps)
- Swipe delete to remove checklist
- Info tooltip explaining import format
- Persistent state during session

### 9.5 W&B (Weight and Balance)

Open: **Menu → W&B**

Functions:

- **Status Card**: green "Within Limits" or red "Outside Limits" indicator with CG position and total weight

- **Interactive CG Envelope Chart**:
  - Scatter plot showing weight (Y-axis) vs arm (X-axis)
  - Blue dots: envelope boundary points
  - Large dot: current CG position (green if inside, red if outside)
  - Tap chart in edit mode to add/remove envelope boundary points
  
- **Chart Configuration** (edit mode):
  - Arm Min/Max values
  - Weight Min/Max values
  - Customizable envelope boundary points

- **Weight Items Table**:
  - 20 editable weight entries
  - Item description, weight (lbs), arm (inches)
  - Auto-calculated moment (weight × arm)
  - Running totals: Total Weight, CG (arm), Total Moment
  - Color-coded border (green/red based on limits)

Use **Edit/Save** toggle to modify and persist. Select W&B profile from dropdown. Swipe left to delete profile.

### 9.6 Log Book

Open: **Menu → Log Book**

Features:

- **Summary Card**:
  - Total Hours, Total Landings, Total Approaches
  - Analytics button to view dashboard

- **Flight List**:
  - Flight time (hours), aircraft make/model (tail)
  - Date, route
  - Day/Night landings, instrument approaches
  - Tap entry to edit, or use FAB to add new entry

- **Log Entry Form** (sections):
  - Flight Info: Date, Aircraft Tail, Type, Route
  - Flight Time: Total, Day, Night, Cross Country, Solo
  - Pilot Function: PIC, SIC, Dual Received, Instructor, Examiner
  - Instrument: Actual IMC, Simulated, Approaches, Holds
  - Landings: Day, Night
  - Training & Simulation: Ground Time, Simulator, Instructor Name/Certificate
  - Remarks: Free-form notes

- **CSV Import/Export**:
  - Import from CSV file (header row required)
  - Export to CSV (share via system share sheet, not Linux)
  - Info tooltip explaining format

#### Logbook Dashboard (Details)

Open by tapping **Details** button:

- **Currency Status Card**: Day currency (3 landings/90 days), Night currency (3 landings/90 days), IFR currency (6 approaches/6 months)
- **Summary Card**: Total hours, PIC, Night, XC, Landings, Approaches
- **Filters**: Year, Aircraft Type, Tail Number, Remarks keywords (Check Ride, IPC, Flight Review, Favorite)
- **Bar Charts**:
  - Flight Hours by Year
  - Hours by Aircraft Type
  - Hours by Tail Number
  - Hours by Category (Solo, Dual, PIC, SIC, Day, Night, IMC, XC, etc.)
  - Landings & Approaches
- **Filtered flight list**: scrollable list of filtered entries

### 9.7 IO (Bluetooth) — Android only

Open: **Menu → IO**

Functions:

- **Device Discovery**: auto-discovery starts when screen opens
- **Device List**: shows device name, address, signal strength (RSSI in dBm)
  - RSSI color-coded: green = strong, red = weak
  - Icons indicate connection status: connected (↔), paired/bonded (link icon)
- **Device Operations** (tap device for dialog):
  - **Pair**: bond with unpaired device
  - **Unpair**: remove device bond
  - **Connect**: establish Bluetooth SPP connection (for paired devices)
- **Connection Status Bar**: shows currently connected device with disconnect button

Connected stream feeds external data input into app parser for GPS, traffic, weather, AHRS.
Also used by Plan Transfer for sending plans to devices and autopilot output for navigation data.

### 9.8 Donate (not iOS/macOS)

Open: **Menu → Donate**

- Shows donation information and links
- Selectable donation URL: apps4av.com/donate
- Supports app development

### 9.9 Help

Open: **Menu → Help**

- Opens the User Manual PDF for in-app reference.
- Available on platforms that support PDF viewing (not Linux).

---

## 10) Notes Screen

### 10.1 How to access

On MAP tab, tap the notes/pen (transcribe) icon in bottom-right controls.

### 10.2 Features

- **Freehand drawing** with finger or stylus
- **Color choices**: Black/White (theme-adaptive), Red, Green
- **Eraser mode**: tap cleaning services icon in toolbar (wide stroke eraser)
- **Undo/Redo**: full stroke history
- **Clear canvas**: eraser icon in app bar
- **Save snapshot**: saves to Documents/notes as `notes_<timestamp>.png`
- **Auto-save**: current sketch autosaves on exit and reloads next time

### 10.3 Aviation background sheets

Use the sheet icon in the app bar to select a background template for common aviation communications:

| Sheet | Purpose |
|-------|---------|
| None | Blank canvas |
| Cost | Flight times (Hobbs, Tach, Fuel, Oil) |
| ATIS | VFR ATIS copydown fields (Airport, ATIS letter, weather, runways, NOTAMs) |
| CRAFT | IFR clearance (Clearance limit, Route, Altitude, Frequency, Transponder) |
| Clearance | VFR flight following clearance |
| Ground Taxi | Ground control taxi instructions |
| Tower Takeoff | Tower takeoff clearance |
| Departure | Departure control contact |
| Approach | Approach control contact |
| Tower Landing | Tower arrival/landing |
| Ground Landed | Ground control after landing |

Each sheet maintains its own saved sketch state. Switching sheets saves the current sheet and loads the new one.

### 10.4 Number keypad

Tap the dialpad icon in the toolbar to display an on-screen keypad:

**Number pad (default):**
- Digits 0-9, decimal point
- Space, newline, backspace
- **C** (Clear): removes the last text entry; press repeatedly to remove more
- **ABC**: switches to QWERTY letter keyboard

**QWERTY keyboard:**
- Letters A-Z in standard QWERTY layout
- Space, backspace, newline
- **C** (Clear): removes the last text entry
- **123**: switches back to number pad

**General usage:**
- **Tap anywhere on canvas** while keypad is active to create a new text entry at that location
- Type to add text at the current location, then tap elsewhere to add text at another spot
- Supports multiple text entries at different positions on the same sheet
- All text entries are saved with the sheet and persist across sessions

---

## 11) Pro Services (iOS/Android only)

### 11.1 Access

From MAP top-right account icon, or by routed requests from some features (e.g., AI Details in Business tab).

### 11.2 Login and subscription flow

- Sign in/register with email authentication (Firebase)
- Paywall handled through RevenueCat entitlement (`Pro`)
- After login, bottom sheet shows available Pro features

### 11.3 Flight Intelligence (AI)

Screen title: **Flight Intelligence**

Powered by Gemini 2.5 Pro with Google Search integration.

Capabilities:

- Ask free-form aviation/trip questions (internet required)
- Question must be 256 characters or less
- Context limit: 10,000 tokens

**Context toggles** (tap to highlight, highlighted context sent with question):
- **Logbook icon**: include your 50 most recent logbook entries
- **Aircraft icon**: include tail number and type from first aircraft
- **Route icon**: include current flight plan
- **Cloud icon**: include winds aloft from departure and destination

**Query/answer workflow**:
- Type question in text box
- Tap **Ask** to submit
- Response appears in text box with disclaimer
- History drawer (clock icon): view previous questions/answers, choose question, show answer, delete history item
- **Clear (X)** button clears text box

**Disclaimer**: Responses are generated by an AI model and may not be accurate or reliable. Do not use when life, health, property are at stake.

### 11.4 Backup/Sync

Screen title: **Backup/Sync**

Cloud operations for `user.db` using Firebase Storage:

- **Backup** (upload icon): upload local database to cloud storage
  - Warning: overwrites existing cloud backup
- **Restore** (download icon): download cloud backup over local database
  - Warning: overwrites existing local data
- Progress indicator shows transfer percentage
- Both actions show confirmation warnings before proceeding
- Data stored under user's Firebase UID

---

## 12) Warnings and Troubleshooting Drawer

When warning state is active, a red alert icon appears on MAP top-right.
Tap it to open issues drawer.

Possible issue items:

- GPS permission denied (opens app settings)
- GPS disabled (opens location settings)
- No GPS lock
- Critical data/charts missing (shortcut to Download)
- Data expired (shortcut to Download)
- Runtime exception notices

---

## 13) Data Lifecycle and Auto-Update Behavior

- Weather downloads refresh periodically (10-minute cycle in storage timer).
- GPS source modes (tap `SRC` tile to cycle):
  - **Auto**: Prefers external GPS when available, falls back to internal after 30s timeout. Shows `Internal-A` or `External-A`.
  - **Internal**: Uses only internal GPS, discards external GPS data. Shows `Internal` with green background.
  - **External**: Uses only external GPS, discards internal GPS data. Shows `External` with blue background.
- Flight status tracks taxi/airborne transitions and accumulates flight time.
- External autopilot/NMEA sentence output is generated continuously while app is running and IO connection exists.
- Track recording continues while Tracks layer is enabled; saves to KML when layer is turned off.

---

## 14) Quick Feature Path Index

| Feature | Path |
|---------|------|
| Download charts/data | `MAP → Menu → Download` |
| Read weather docs / import files | `MAP → Menu → Documents` |
| View saved tracks (KML) | `MAP → Menu → Documents → tracks folder → tap KML file` |
| Create logbook from track | `Documents → tracks → tap KML → 2D Map → Log Flight` |
| Create folder for documents | `MAP → Menu → Documents → folder icon in app bar` |
| Build or modify plan | `PLAN tab` |
| File FAA plan | `PLAN → Actions → Brief & File` |
| Manage filed plans | `PLAN → Actions → Manage` |
| Load reversed plan | `PLAN → Actions → Load & Save → 3-dot menu → Load Reversed` |
| Create IFR preferred route | `PLAN → Actions → Create → Create IFR Preferred Route` |
| Show recent ATC routes | `PLAN → Actions → Create → Show IFR ATC Routes` |
| Send plan to device (Android) | `PLAN → Actions → Transfer` |
| Destination details | Long-press on map or tap FIND result |
| Show plates for airport | Destination popup `Plates` or `PLATE tab` |
| Configure aircraft | `MAP → Menu → Aircraft` |
| Change aircraft map icon | `MAP → Menu → Aircraft → icon dropdown in app bar` |
| Checklist operations | `MAP → Menu → Check Lists` |
| Weight and balance | `MAP → Menu → W&B` |
| Logbook + dashboard | `MAP → Menu → Log Book` |
| Logbook statistics | `MAP → Menu → Log Book → Details` |
| Currency status | `MAP → Menu → Log Book → Details` (currency card) |
| Bluetooth pairing/connection | `MAP → Menu → IO` (Android) |
| Notes/drawing | `MAP → Notes icon` |
| Notes with aviation sheet | `MAP → Notes icon → sheet icon → select template` |
| Notes number keypad | `MAP → Notes icon → dialpad icon` |
| Pro AI | `MAP top-right account icon → Flight Intelligence` |
| Cloud backup/restore | `MAP top-right account icon → Backup/Sync` |
| User Manual (Help) | `MAP → Menu → Help` |
| Donate | `MAP → Menu → Donate` (not iOS/macOS) |
| CAP Grid overlay | `MAP → Layers → CAP Grid slider > 0` (zoom to level 9+) |
| Enable wind vectors | `MAP → Layers → Wind Vectors slider > 0` (use altitude slider) |
| Enable ceiling overlay | `MAP → Layers → Ceiling slider > 0` (use altitude slider) |
| Change GPS source mode | Tap `SRC` tile in instrument bar |
| Measure distances | `MAP → Ruler icon → long-press map to add points` |
| Rubber band waypoints | `MAP → Rubber banding icon → long-press and drag waypoints` |
| Insert waypoint at position | `PLAN → long-press waypoint row → FIND → select destination` |
| View winds & terrain analysis | `PLAN → analytics icon → tap diagram for details` |

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
   - Ownship updates smoothly
   - Traffic symbols appear (if in range)
   - Weather products populate
7. If needed, open warning drawer from red icon and resolve GPS/data warnings.

### UC-02: Connect an external ADS-B/GPS receiver over Bluetooth (Android)

1. Open `MAP → Menu → IO`.
2. Wait for device discovery to populate the list.
3. Select your receiver from list.
4. Pair (if needed), then tap **Connect**.
5. Confirm status line shows connected device.
6. Return to map and enable `Traffic` / `Weather` layers as needed.
7. To disconnect: `IO → Disconnect`.

### UC-03: Rubber-band a route directly on the map

Use this to adjust waypoints graphically.

1. Ensure your route has waypoints (`PLAN` tab or destination popup `+Plan`).
2. Go to `MAP`.
3. Tap the **rubber banding** icon (decision arrow) to enable it (icon turns red).
4. Long-press a waypoint marker or label and drag to a new position.
5. Release to snap/update from database lookup and rebuild route geometry.
6. Turn rubber banding off when done to avoid accidental edits.

### UC-04: Build a flight plan from scratch (quick VFR workflow)

1. Open `PLAN` tab.
2. Add waypoints using either:
   - `FIND` tab → tap item → `+Plan` (insert) or `↓Plan` (append to end), or
   - `MAP` long-press destination popup → `+Plan` (insert) or `↓Plan` (append to end), or
   - **Long-press** an existing waypoint row in `PLAN` to insert after it (opens FIND; next selection inserts after that waypoint).
3. Reorder legs by long-press and drag in `PLAN`.
4. Tap a leg to make it current.
5. Set `ASpd`, `GPH`, and `Alt` at bottom of `PLAN`.
6. Open nav-log (analytics icon) to review:
   - Leg calculations (double-tap grid to reset zoom)
   - Combined winds & terrain diagram (green=tailwind/safe, red=headwind/terrain warning)
   - Tap on diagram for detailed info at any point
7. Save the route: `PLAN → Actions → Load & Save → Save`.

### UC-05: Create an IFR route automatically

1. Open `PLAN → Actions → Create`.
2. In Route field:
   - Enter route text and use **Create As Entered**, or
   - Enter `DEPART DEST` and use **Create IFR Preferred Route**, or
   - Use **Show IFR ATC Routes** to view recent ATC route options.
3. When route is loaded, return to `PLAN` to review/reorder waypoints.

### UC-06: File a flight plan with the FAA

Prereq: set your 1800wxbrief-compatible email in onboarding.

1. Build/verify your route in `PLAN`.
2. Open `PLAN → Actions → Brief & File`.
3. Fill required fields (aircraft ID/type, rule, departure, destination, route, times, fuel, POB, etc.).
4. Use quick-fill buttons:
   - "Planned" buttons for departure/destination/route from current plan
   - Aircraft buttons to fill from stored aircraft profiles
5. Tap:
   - **Get Email Brief** for briefing email, and/or
   - **Send to FAA** to file.
6. Check status indicator (checkmark=success, info icon=error with tooltip).

### UC-07: Activate, close, or cancel an FAA flight plan

1. Open `PLAN → Actions → Manage`.
2. Find your plan in the list (color-coded by status).
3. Use action by state:
   - `PROPOSED` (blue): **Depart** (choose time with sunrise/sunset reference) to activate
   - `ACTIVE` (green): **Close** after landing
   - Non-active: **Cancel** if no longer needed

### UC-08: Quickly divert to a nearby airport

1. On `MAP`, long-press near destination area.
2. In popup, review nearby list and tap a candidate airport.
3. Tap `→D` to set Direct-To and center map.
4. Optional:
   - Tap `Plates` for immediate airport diagrams/procedures
   - Add to full route with `+Plan`

### UC-09: Use plates with procedure profile and add procedure to plan

1. Open `PLATE` tab.
2. Select airport (bottom-right selector).
3. Select desired plate (bottom-left selector, color-coded by type).
4. Use procedure menu (plus icon):
   - Choose procedure to show profile card
   - Use `+Plan` to append procedure to route.
5. Keep instruments visible on plate using top-right show/hide toggle.
6. Close profile card with X button when done.

### UC-10: Save your flown track and retrieve it from Documents

1. In `MAP`, keep `Tracks` layer on during flight (opacity > 0).
2. When done, set `Tracks` layer opacity to `0` in Layers menu.
3. App saves track automatically as KML in Documents/tracks folder.
4. Open `MAP → Menu → Documents → tracks` to access/share file.

### UC-10a: View a saved track and create a logbook entry

1. Open `MAP → Menu → Documents → tracks`.
2. Tap a KML file to open the Track Viewer.
3. Use view icons to switch between 2D Map, Altitude Profile, and 3D View.
4. In 2D Map view, tap **Log Flight** to create a logbook entry from the track.
5. The entry auto-fills route (nearest airports), time (from timestamps or distance/TAS), and aircraft info from selected profile.

### UC-10b: Use aviation sheets for IFR clearance copydown

1. On `MAP`, tap the notes/pen icon.
2. Tap the sheet icon in the app bar.
3. Select **CRAFT** for IFR clearance fields.
4. Use the number keypad (dialpad icon) to type frequencies, altitudes, or squawk codes.
5. **Tap on the canvas** to position the typed text exactly where you want it (e.g., next to the frequency field).
6. Use freehand drawing to fill in route or other notes.
7. The sheet auto-saves when you exit or switch sheets.
8. Return anytime to continue where you left off; each sheet maintains its own state.

### UC-11: Import a GeoJSON overlay and display it on map

1. Open `MAP → Menu → Documents`.
2. Tap **Import** and select a `.geojson` file.
3. Open `MAP` and set `GeoJSON` layer opacity > 0.
4. Imported polygons/markers now draw on the map.

### UC-12: Transfer your plan to an NMEA-compatible device (Android)

This feature sends flight plans using standard NMEA 0183 RTE/WPL sentences.

**Note:** Modern Garmin panel-mount avionics (G3X Touch, GTN, GNS series) do NOT support this protocol—they require Garmin's proprietary Connext protocol available only in Garmin Pilot and ForeFlight. For those devices, use Garmin Pilot for flight plan transfer.

1. Build your route with at least 2 waypoints.
2. Connect your NMEA-compatible device in `MAP → Menu → IO`.
3. Open `PLAN → Actions → Transfer`.
4. Confirm connected device label and connection status.
5. Tap **Send to Garmin**.
6. Wait for success toast/status.

### UC-13: Back up and restore app data (Pro)

1. Open Pro Services from account icon on MAP (top-right).
2. Sign in and pass entitlement/paywall if required.
3. Open `Backup/Sync` (from bottom buttons after login).
4. Use:
   - **Backup** (upload icon) to upload local `user.db`
   - **Restore** (download icon) to overwrite local data from cloud copy
5. Confirm prompts carefully (both operations overwrite existing data).
6. Progress percentage shows during transfer.

### UC-14: Get flight help from community resources

1. In onboarding or browser, open Apps4Av forum:
   - `https://groups.google.com/g/apps4av-forum`
2. Search existing threads for similar workflows/devices.
3. Post issue details:
   - Platform/device
   - Receiver type
   - What screen/action failed
   - Any warning drawer messages

### UC-15: Use the CAP Grid overlay for search and rescue

1. Go to `MAP → Layers`.
2. Set **CAP Grid** opacity > 0.
3. Zoom to level 9 or higher (grid only renders at sufficient zoom).
4. Grid squares appear with identifiers (e.g., BOS42, SEA123).
5. Use grid coordinates for communication with ground teams or other aircraft.

### UC-16: Choose a different aircraft icon on the map

1. Open `MAP → Menu → Aircraft`.
2. In the app bar, tap the aircraft icon dropdown.
3. Select from: plane, helicopter, or canard.
4. The map will display your selected icon for ownship.

### UC-17: Load a plan in reverse order for a return flight

1. Open `PLAN → Actions → Load & Save`.
2. Find your saved outbound plan.
3. Tap the 3-dot menu on the plan.
4. Select **Load Reversed**.
5. The plan loads with waypoints in reverse order, ready for your return trip.

### UC-18: Check your pilot currency status

1. Open `MAP → Menu → Log Book`.
2. Tap the **Details** button.
3. View the Currency Status Card at the top showing:
   - Day currency: 3 landings in last 90 days
   - Night currency: 3 night landings in last 90 days
   - IFR currency: 6 approaches in last 6 months
4. Green = current, Red = not current

### UC-19: Measure distance and bearing on the map

1. On `MAP`, tap the **Ruler** icon (compass) to enable measure mode (turns red).
2. Long-press on the map to place your first point.
3. Long-press again to add additional points.
4. Distance (NM) and bearing (degrees) are shown between points.
5. Tap the Ruler icon again to disable and clear measurements.

### UC-20: Insert a waypoint at a specific position in your plan

1. Open `PLAN` tab with an existing route.
2. Find the waypoint you want to insert after.
3. **Long-press** that waypoint row.
4. The app switches to `FIND` tab.
5. Search for or select the waypoint you want to insert.
6. Tap `+Plan` or `↓Plan` — the new waypoint inserts after the long-pressed position.

### UC-21: Analyze winds and terrain along your route

1. Open `PLAN` tab and ensure you have a route with at least 2 waypoints.
2. Set your planned altitude using the `Alt` field at the bottom.
3. Tap the analytics icon (chart) to open the Navigation Log.
4. View the **Winds & Terrain En Route** diagram:
   - Green cells = tailwind at that altitude/position
   - Red cells = headwind at that altitude/position
   - Cyan horizontal line = your planned altitude
   - Green terrain line = terrain safely below your altitude
   - Red terrain line = terrain at or above your altitude (warning)
5. **Tap anywhere** on the diagram to see detailed info:
   - Wind direction and speed
   - Headwind/tailwind component
   - Terrain elevation
   - Course at that point
6. Use waypoint tick marks at the bottom to identify positions along your route.

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
- For Bluetooth receivers (Android): `Menu → IO`, pair/connect, then return to map.
- Source threads:
  - GPS source discussion:  
    `https://groups.google.com/g/apps4av-forum/c/e0ujCJQX1s8`
  - In-flight ADS-B issues:  
    `https://groups.google.com/g/apps4av-forum/c/ZP2E9l35Dk8`
  - Android IO functionality:  
    `https://groups.google.com/g/apps4av-forum/c/WI-BcDK7rT0`

### FAQ-02: How do I transfer a plan to an external device?

- Build a route with at least 2 waypoints.
- On Android, connect device in `Menu → IO`.
- Open `PLAN → Actions → Transfer`, then **Send to Garmin**.

**Important compatibility note:** This feature uses standard NMEA 0183 RTE/WPL sentences. It works with devices that accept NMEA waypoint/route input (older handhelds, some autopilots, marine GPS). 

**It does NOT work with modern Garmin panel-mount avionics** (G3X Touch, GTN 650/750, GNS 430W/530W). These use Garmin's proprietary Connext protocol, which Garmin restricts to their own Garmin Pilot app and ForeFlight. If you have these avionics, use Garmin Pilot (free) to transfer flight plans wirelessly.

- Source threads:
  - Testing Garmin transfer:  
    `https://groups.google.com/g/apps4av-forum/c/k958J5yLyR4`
  - Importing/transfer conversation:  
    `https://groups.google.com/g/apps4av-forum/c/acmWm72qITY`

### FAQ-03: Where do I enable new wind/ceiling map features?

- `MAP → Layers`:
  - Enable **Wind Vectors** and/or **Ceiling**
  - Use right-side altitude slider to change displayed altitude context
- Source threads:
  - New features v83/v84:  
    `https://groups.google.com/g/apps4av-forum/c/qac4-Bb-gVE`  
    `https://groups.google.com/g/apps4av-forum/c/Xvhc9yeE42A`

### FAQ-04: My track logs are empty. How do I save valid KML logs?

- Keep `Tracks` layer ON (opacity > 0) during flight.
- After flight, turn `Tracks` layer OFF (opacity = 0) — this saves KML to Documents/tracks folder and clears active track buffer.
- Open `Documents → tracks` and verify non-empty KML before sharing.
- Tap the KML file to view it in Track Viewer with 2D map, altitude profile, and 3D terrain views.
- Use **Log Flight** button to create a logbook entry directly from the track.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/goPy8KQpfik`

### FAQ-05: Where are FBO/business details?

- On `PLATE` screen, when an airport diagram is active and business data is available, use the right-side business selector (three dots icon).
- In destination popup, the **Business** tab shows nearby businesses with AI **Details** button (Pro feature).
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/oMOR-gaIqis`

### FAQ-06: What are the colored rings on map?

- In the `Circles` layer:
  - **Black rings**: fixed 2/5/10 NM reference rings
  - **Blue ring**: speed-based 1-minute travel distance
  - **Purple ring**: glide circle based on aircraft sink rate, winds aloft, terrain, and altitude
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/VJ0S3ejWPC8`

### FAQ-07: My waypoints appear in wrong order. Can I reorder or insert quickly?

- **Reorder**: In `PLAN`, long-press and drag rows to reorder legs.
- **Insert at specific position**: Long-press a waypoint row to insert after it (opens FIND; next selection inserts after that waypoint).
- **Set current leg**: Tap a waypoint row.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/T-m4BWZynMg`

### FAQ-08: How do I enter an ATC reroute quickly?

- Open `PLAN → Actions → Create`.
- Use **Create As Entered** and paste/type reroute string (space-separated waypoints/airways).
- Then review/reorder in PLAN list if needed.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/ukaXEEhpvS0`

### FAQ-09: Download/cycle issues - what to try first?

- In `Download` screen:
  - Try **This Cycle** vs **Next Cycle**
  - Try **Main Server** vs **Backup Server**
  - Keep download screen open until completion (exiting can abort incomplete downloads)
- Source threads:
  - Cycle download issue:  
    `https://groups.google.com/g/apps4av-forum/c/LS_VaqKEJxw`
  - Background download request:  
    `https://groups.google.com/g/apps4av-forum/c/XcoQzwpCxlw`

### FAQ-10: FAA IFR preferred route tools not working - what now?

- Ensure app is updated to latest release and internet is available.
- Confirm your 1800wxbrief-compatible email is configured.
- Retry via `PLAN → Actions → Create` and `Brief & File`.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/0wHqcJT-WiY`

### FAQ-11: Is Flight Intelligence (AI) available on desktop?

- Current Pro AI workflows are targeted for iOS/Android only.
- Access from map account icon → Pro Services → Flight Intelligence.
- Uses Gemini 2.5 Pro with Google Search integration.
- Source threads:
  - AI feature thread:  
    `https://groups.google.com/g/apps4av-forum/c/wWZUn6TNG1w`
  - Desktop/pro services request:  
    `https://groups.google.com/g/apps4av-forum/c/XcoQzwpCxlw`

### FAQ-12: Can I use AvareX with X-Plane/simulator feeds?

- AvareX accepts external NMEA/GDL90-like streams via UDP listener ports (4000, 43211, 49002).
- For simulator setups, configure simulator/network output accordingly.
- Source thread:  
  `https://groups.google.com/g/apps4av-forum/c/QOfnQ-pkT0w`

### FAQ-13: What is the CAP Grid layer?

- Civil Air Patrol grid overlay for search and rescue operations.
- Shows grid identifiers (e.g., BOS42, SEA123) at zoom level 9+.
- Enable via `MAP → Layers → CAP Grid` opacity > 0.
- Covers all US sectional chart areas.

### FAQ-14: How do I view my flight in 3D?

- Record your flight with `Tracks` layer enabled.
- Turn `Tracks` off to save the KML file.
- Open `Documents → tracks` and tap the KML file.
- Use the 3D View icon (AR) to see interactive 3D visualization with terrain and topo map texture.

### FAQ-15: How do I check if I'm current to fly?

- Open `MAP → Menu → Log Book → Details`.
- The Currency Status Card shows your currency for:
  - Day VFR (3 landings in 90 days)
  - Night (3 night landings in 90 days)
  - IFR (6 approaches in 6 months)
- Status is automatically calculated from your logbook entries.

---
