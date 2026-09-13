# AvareX

Avare, written in Flutter. Runs on Linux, Windows, MacOS, iOS, Android, and Raspberry Pi.

AvareX is a pilot's all in one electronic flight bag solution.

By Apps4Av.

## User Manual

A comprehensive, code-derived user manual is available at:

- [USER_MANUAL.md](USER_MANUAL.md)

## Getting Started



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

On `master`, a version change in `pubspec.yaml` uploads Android to the Play **internal** track, iOS to **TestFlight**, and Windows to a Partner Center **draft** submission (package uploaded, not committed, publish mode Manual). A version change in `snap/snapcraft.yaml` uploads Linux to Snap **edge**. Builds still go to apps4av.org on every push. Nothing is sent to production, stable, or a public store listing until you submit the Windows draft in Partner Center. The live listing still shows the last published package until that draft is submitted; check the draft's packages, not the published listing.

To retry a Windows draft upload without bumping the version: **Actions → Windows → Run workflow** (branch `master`).

Play and TestFlight “What’s new” is generated from the **AvareX Releases** section in `USER_MANUAL.md` (`bash .github/scripts/update-whatsnew.sh`). Do not hand-edit `store/whatsnew/whatsnew-en-US`.

Required secrets (that store is skipped if the credential is unset):

- Play internal: `PLAY_STORE_SERVICE_ACCOUNT_JSON`
- TestFlight: `APPSTORE_ISSUER_ID`, `APPSTORE_API_KEY_ID`, `APPSTORE_API_PRIVATE_KEY`
- Snap edge: `SNAPCRAFT_STORE_CREDENTIALS` (`snapcraft export-login --snaps=avarex --channels=edge snapcraft-login.txt`)
- Windows draft: `PARTNER_CENTER_TENANT_ID`, `PARTNER_CENTER_SELLER_ID`, `PARTNER_CENTER_CLIENT_ID`, `PARTNER_CENTER_CLIENT_SECRET`

Microsoft version scheme: pubspec.yaml (versions go like 1.0.9.0, last digit must be 0)

Apple version scheme: pubspec.yaml 0.0.9+9

Google version scheme: pubspec.yaml 0.0.9+9  (+9) is what shows up in the package)

Snap version scheme: snap/snapcraft.yaml 0.0.9


