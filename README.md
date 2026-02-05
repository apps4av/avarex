# AvareX

Avare, written in Flutter. Runs on Linux, Windows, MacOS, iOS, Android, and Raspberry Pi.

AvareX is a pilot's all in one electronic flight bag solution.

By Apps4Av.

## Getting Started

## Garmin Connext Flight Plan Transfer (Android)

1. Open the IO screen and connect to your Garmin device over Bluetooth.
2. Go to Plan -> Actions -> Transfer.
3. Tap "Send to Garmin" to transmit the current flight plan (NMEA RTE/WPL).

### Downloading


** Windows 

Download on Windows using Microsoft Store.

** MacOS

Download on Apple App Store from your Mac with Apple Silicon.

** Linux

Download on Linux using Snap Store.

** iOS

Download on Apple App Store from your iPhone or iPad.

** Android

Download on Google Play Store from your Android device.

** Raspberry Pi

Download at https://github.com/apps4av/avarex/actions/workflows/arm64.yaml from your Pi. 

Tested on 64-bit Raspberry Pi OS (may run on other configurations).
 - Pi 5 with 8 GB memory
 - Pi 4 with 1 GB memory
 - Prerequisites: sudo apt-get install libgtk-3-0 libblkid1 liblzma5 libsqlite3-dev

## Store Consoles

Google / Android: https://play.google.com/console

iOS, MacOS: https://appstoreconnect.apple.com/login

Linux: https://snapcraft.io

Windows: https://partner.microsoft.com/en-us/dashboard/home

## Store Locations

Google / Android : https://play.google.com/store/apps/details?id=com.apps4av.avaremp

iOS, MacOS: https://apps.apple.com/us/app/avarex/id6502421523

Linux: https://snapcraft.io/avarex

Windows: https://apps.microsoft.com/detail/9mx4hkl30mww?hl=en-us&gl=US

## Building:

Github Actions builds all store builds.

Microsoft version scheme: pubspec.yaml (versions go like 1.0.9.0, last digit must be 0)

Apple version scheme: pubspec.yaml 0.0.9+9

Google version scheme: pubspec.yaml 0.0.9+9  (+9) is what shows up in the package)

Snap version scheme: snap/snapcraft.yaml 0.0.9


