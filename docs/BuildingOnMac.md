# Building on a Mac

## Prerequisites

- macOS with **Xcode 15+** (iOS 16 SDK).
- [Homebrew](https://brew.sh) + **XcodeGen**.
- Physical iPhone (A11+ recommended) + free or paid Apple Developer account for signing.

## Generate & run

```bash
brew install xcodegen
cd Panorama360
xcodegen generate          # creates Panorama360.xcodeproj from project.yml
open Panorama360.xcodeproj
```

In Xcode:

1. Target **Panorama360** → **Signing & Capabilities** → select your Team.
2. Choose your plugged-in iPhone as destination (not Simulator).
3. **⌘R**. Grant Camera + Motion on first launch.

## Regenerating the project

`project.yml` is the source of truth. Never hand-edit `.xcodeproj` long-term — change `project.yml` and run `xcodegen generate` again. The `.xcodeproj` is gitignored.

## Release build locally

```bash
xcodegen generate
xcodebuild \
  -project Panorama360.xcodeproj \
  -scheme Panorama360 \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

For an unsigned IPA matching CI, see `.github/workflows/build-ipa.yml`.

## Common first-build fixes

This codebase was authored without a live Swift toolchain on Windows. If Xcode reports a signature mismatch:

1. Read the exact error in the Issue navigator.
2. Fix the one API call / availability annotation.
3. Rebuild — most issues are one-liners.

## Optional OpenCV

See [OpenCVIntegration.md](OpenCVIntegration.md).
