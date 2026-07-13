# Changelog

## [1.1.0] — 2026-07-13

### Added
- First-launch onboarding + guided tutorial room (8-point sphere).
- CrashReporter with C-compatible uncaught exception handler.
- Camera runtime-error surfacing and capture failure UI.

### Fixed
- Crash ~3s after launch (video sample queue was released after `configure()`).
- Multiple Xcode 16 / AVFoundation / Metal API mismatches for CI IPA builds.
- GitHub Actions: macos-15 + Xcode 16 for XcodeGen objectVersion 77.

## [1.0.0] — 2026-07-12

### Added

- Guided 360° capture with ARKit/CoreMotion orientation and floating sphere points.
- Auto-capture gate: alignment, stability, focus, exposure, sharpness, cooldown.
- Pure-Apple Metal sphere projector stitcher (orientation-aware equirectangular).
- Optional OpenCV stitcher hook (`#if canImport(opencv2)`).
- Interactive Metal 360° viewer (drag, pinch, gyro).
- XcodeGen `project.yml` (no committed `.xcodeproj`).
- GitHub Actions workflow: unsigned IPA artifact on macOS runners.
- Docs: Architecture, Sistema (PT), Building on Mac, Installing on Windows, OpenCV.
