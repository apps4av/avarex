# AvareX User Manual

Version: October 2025

---

## Overview
AvareX is the next-generation, cross-platform evolution of the Apps4Av ecosystem, designed to provide pilots with a modern, fast Electronic Flight Bag (EFB). It delivers core Avare capabilities—offline charts, flight planning, GPS navigation—while introducing a refreshed UI, powerful search, and features like GeoJSON overlays and shareable notes. This manual compiles instructions and common Q&A from community discussions on the Apps4Av forum (`https://groups.google.com/g/apps4av-forum`) to help you get productive quickly.

> Note: This guide focuses on AvareX, the newer app in the Apps4Av family. For the classic Avare app, some workflows and menus differ.

---

## System Requirements
- **Platforms**: Android, Windows, Linux (including Raspberry Pi).
- **Android**: Android 9+ recommended.
- **Raspberry Pi**: Raspberry Pi 5 with 16 GB RAM recommended for heavier use and multiple instances (community guidance).
- **GPS/ADS-B**: Internal GPS supported. For ADS‑B In (traffic/weather), use compatible receivers as supported by your platform.

---

## Installation
### Android
1. Install from Google Play (search "AvareX").
2. Open the app and grant Location and Storage permissions.
3. On first run, download needed charts/data.

### Windows
1. Download the latest AvareX release from the official source.
2. Run the installer and follow prompts.
3. Launch the app and choose a data folder.

### Linux / Raspberry Pi
1. Obtain the Linux build from the official source.
2. Install dependencies per your distro.
3. Launch AvareX and select a writable data directory.

---

## First Run & Data Download
1. Launch AvareX.
2. Open the Downloads/Data page.
3. Select regions and products:
   - Sectionals/IFR Enroute
   - TACs/Heli
   - A/FD, Procedures (plates)
   - Terrain/Obstacles
4. Tap Download. Ensure stable internet and adequate storage.

> Tip: Keep data current. Many products update every 28 days.

---

## User Interface Overview
- **Map**: Primary moving map with overlays (route, weather, traffic).
- **Top Bar/Ribbon**: Quick access to Search, Plan, Plates, Weather, NOTAMs, Settings.
- **Bottom Info/Sheet**: Contextual details for selected items (airports, waypoints, NOTAMs, METAR/TAF).
- **Layers/Overlays**: Toggle charts, terrain, traffic, weather, airspace.

---

## Core Workflows
### Create a Flight Plan
1. Open the Plan page.
2. Enter departure and destination (ICAO or name).
3. Add intermediate waypoints as needed.
4. Save the plan.

- **Reorder waypoints**: Drag to rearrange.
- **Delete a waypoint**: Swipe it away (similar to deleting an email).
- **Activate**: Send to map and follow magenta line.

### Direct-To
1. On the map, search or long-press an airport/nav fix.
2. Choose Direct-To to navigate immediately.

### Plates & Airport Diagrams
1. Go to Plates.
2. Select an airport.
3. Download and view approach plates, SIDs/STARs, and diagrams.

> Community note: Auto-showing airport diagrams when on the surface has been requested and may come in future updates.

### Weather (METAR/TAF) and NOTAMs
- Long-press an airport on the map, then open METAR/TAF or NOTAM tabs in the bottom sheet.
- Ensure internet connectivity for latest data.
- NOTAM filtering by selected airport is a common user request; behavior may evolve.

### GeoJSON Overlays (Advanced)
- Import GeoJSON to overlay custom shapes/imagery for special operations or training.
- Available in recent builds.

### Notes (Kneeboard)
- Create notes and export as JPEG for sharing or briefing packages.

---

## Map & Navigation Tips
- **Pan/Zoom**: Two-finger pinch/zoom, drag to pan. Double-tap to center.
- **Track Up vs North Up**: Toggle in Settings.
- **Airspace/Labels**: Use Layers to declutter or add details.
- **Measure Tool**: Long-press and drag to quickly estimate distance/bearing.
- **Nearest**: Use Search/Nearest for quick diversions.

---

## GPS, ADS‑B, and Sensors
- **GPS**: Uses internal device GPS by default. Verify Location permissions are granted.
- **ADS‑B In**: Connect supported receivers for FIS‑B weather and traffic where available. Setup steps vary by device and receiver.
- **Orientation/Sensors**: Calibrate device sensors in Settings if required.

---

## Data Management
- AvareX stores user data (aircraft profiles, settings, routes) in its app data directory.
- To migrate data between devices, copy the user database file (commonly `user.db`) from the source device’s AvareX data folder to the same location on the target device, with the app closed.

> On some platforms, built-in Share may be limited. Manual copy of `user.db` is a reliable fallback.

---

## Settings Highlights
- **Units & Format**: Toggle nautical/statute, feet/meters, UTC/local.
- **Layers**: Enable/disable map overlays like terrain, obstacles, airspace labels.
- **Downloads**: Select coverage areas and auto-update preferences.
- **Connectivity**: Configure network sources and any external receivers.
- **Performance**: Limit overlays on older devices; keep only needed regions downloaded.

---

## Keyboard/Mouse (Desktop)
- **Scroll** to zoom; **right-drag** to pan (varies by OS/build).
- **Ctrl+F** or Search to find airports, navaids, fixes.
- **Resize** windows if panels appear truncated; adjust OS display scaling if needed.

---

## Troubleshooting
- **App won’t open (Android)**: Ensure Android 9+ and the latest AvareX version. Reboot and retry.
- **Crashes on startup**: Update to the latest build; several stability fixes have shipped in recent versions.
- **Sharing data doesn’t work**: Manually copy `user.db` between devices as described under Data Management.
- **Display truncation on Windows**: If a planning pane looks cut off, resize the window or check display scaling.
- **Missing weather/NOTAMs**: Check internet connectivity and refresh.
- **Charts out of date**: Open Downloads and update all products.

---

## FAQ (Collected from community questions)
- **How do I delete a waypoint in a plan?** Swipe the waypoint (like deleting an email).
- **Can I run on Raspberry Pi?** Yes; community guidance suggests a Raspberry Pi 5 with 16 GB RAM for smooth performance and multiple instances.
- **Where are my personal data and plans stored?** In the app’s data directory; migrating `user.db` copies aircraft, routes, and settings.
- **How do I view METAR/TAF?** Long-press an airport on the map and open the METAR/TAF tab.
- **Can I limit NOTAMs to the selected airport?** This has been requested; behavior may change with updates.
- **What’s new versus classic Avare?** AvareX brings a modern UI, improved planning, GeoJSON overlays, and better cross‑platform support. Some menus differ from Avare.

---

## Release Cadence & Updates
- Aeronautical data typically updates every 28 days.
- Check for app updates regularly to receive fixes and new features.

---

## Privacy & Permissions
- **Location** is used for GPS navigation and nearest searches.
- **Storage** is used for charts, plates, terrain, and your saved plans.
- No aviation app replaces pilot judgment; review permissions in your OS settings.

---

## Community & Support
- **Forum**: Apps4Av community forum at `https://groups.google.com/g/apps4av-forum`
- **Issue Reporting**: Search the forum for known issues and post details (device, OS, steps).
- **Learning**: Explore threads for tips on planning, overlays, NOTAM filtering, and Raspberry Pi setups.

---

## Legal & Safety
AvareX is an aid to navigation and planning. Always cross‑check with official sources and maintain pilot‑in‑command responsibility.

---

## Installation
### Android
1. Install from Google Play (search "AvareX").
2. Open the app and grant Location and Storage permissions.
3. On first run, download needed charts/data.

### Windows
1. Download the latest AvareX release from the official source.
2. Run the installer and follow prompts.
3. Launch the app and choose a data folder.

### Linux / Raspberry Pi
1. Obtain the Linux build from the official source.
2. Install dependencies per your distro.
3. Launch AvareX and select a writable data directory.

---

## First Run & Data Download
1. Launch AvareX.
2. Open the Downloads/Data page.
3. Select regions and products:
   - Sectionals/IFR Enroute
   - TACs/Heli
   - A/FD, Procedures (plates)
   - Terrain/Obstacles
4. Tap Download. Ensure stable internet and adequate storage.

> Tip: Keep data current. Many products update every 28 days.

---

## User Interface Overview
- **Map**: Primary moving map with overlays (route, weather, traffic).
- **Top Bar/Ribbon**: Quick access to Search, Plan, Plates, Weather, NOTAMs, Settings.
- **Bottom Info/Sheet**: Contextual details for selected items (airports, waypoints, NOTAMs, METAR/TAF).
- **Layers/Overlays**: Toggle charts, terrain, traffic, weather, airspace.

---

## Core Workflows
### Create a Flight Plan
1. Open the Plan page.
2. Enter departure and destination (ICAO or name).
3. Add intermediate waypoints as needed.
4. Save the plan.

- **Reorder waypoints**: Drag to rearrange.
- **Delete a waypoint**: Swipe it away (similar to deleting an email).
- **Activate**: Send to map and follow magenta line.

### Direct-To
1. On the map, search or long-press an airport/nav fix.
2. Choose Direct-To to navigate immediately.

### Plates & Airport Diagrams
1. Go to Plates.
2. Select an airport.
3. Download and view approach plates, SIDs/STARs, and diagrams.

> Community note: Auto-showing airport diagrams when on the surface has been requested and may come in future updates.

### Weather (METAR/TAF) and NOTAMs
- Long-press an airport on the map, then open METAR/TAF or NOTAM tabs in the bottom sheet.
- Ensure internet connectivity for latest data.
- NOTAM filtering by selected airport is a common user request; behavior may evolve.

### GeoJSON Overlays (Advanced)
- Import GeoJSON to overlay custom shapes/imagery for special operations or training.
- Available in recent builds (e.g., 0.0.40+).

### Notes (Kneeboard)
- Create notes and export as JPEG for sharing or briefing packages.

---

## GPS, ADS‑B, and Sensors
- **GPS**: Uses internal device GPS by default. Verify Location permissions are granted.
- **ADS‑B In**: Connect supported receivers for FIS‑B weather and traffic where available. Setup steps vary by device and receiver.
- **Orientation/Sensors**: Calibrate device sensors in Settings if required.

---

## Data Management
- AvareX stores user data (aircraft profiles, settings, routes) in its app data directory.
- To migrate data between devices, copy the user database file (commonly `user.db`) from the source device’s AvareX data folder to the same location on the target device, with the app closed.

> On some platforms, built-in Share may be limited. Manual copy of `user.db` is a reliable fallback.

---

## Settings Highlights
- **Units & Format**: Toggle nautical/statute, feet/meters, UTC/local.
- **Layers**: Enable/disable map overlays like terrain, obstacles, airspace labels.
- **Downloads**: Select coverage areas and auto-update preferences.
- **Connectivity**: Configure network sources and any external receivers.

---

## Troubleshooting
- **App won’t open (Android)**: Ensure Android 9+ and the latest AvareX version. Reboot and retry.
- **Crashes on startup**: Update to the latest build; several stability fixes have shipped in recent versions.
- **Sharing data doesn’t work**: Manually copy `user.db` between devices as described under Data Management.
- **Display truncation on Windows**: If a planning pane looks cut off, resize the window or check display scaling.
- **Missing weather/NOTAMs**: Check internet connectivity and refresh.
- **Charts out of date**: Open Downloads and update all products.

---

## FAQ (Collected from community questions)
- **How do I delete a waypoint in a plan?** Swipe the waypoint (like deleting an email).
- **Can I run on Raspberry Pi?** Yes; community guidance suggests a Raspberry Pi 5 with 16 GB RAM for smooth performance and multiple instances.
- **Where are my personal data and plans stored?** In the app’s data directory; migrating `user.db` copies aircraft, routes, and settings.
- **How do I view METAR/TAF?** Long-press an airport on the map and open the METAR/TAF tab.
- **Can I limit NOTAMs to the selected airport?** This has been requested; behavior may change with updates.
- **What’s new versus classic Avare?** AvareX brings a modern UI, improved planning, GeoJSON overlays, and better cross‑platform support. Some menus differ from Avare.

---

## Release Cadence & Updates
- Aeronautical data typically updates every 28 days.
- Check for app updates regularly to receive fixes and new features.

---

## Community & Support
- **Forum**: Apps4Av community forum at https://groups.google.com/g/apps4av-forum
- **Issue Reporting**: Search the forum for known issues and post details (device, OS, steps).
- **Learning**: Explore threads for tips on planning, overlays, NOTAM filtering, and Raspberry Pi setups.

---

## Legal & Safety
- AvareX is an aid to navigation and planning. Always cross‑check with official sources and maintain pilot‑in‑command responsibility.

