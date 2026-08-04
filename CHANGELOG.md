# Changelog

## [1.2.0] — 2026-08-04

### Added
- `HorizonLeveler`: per-shot gravity is now recorded and used to level the horizon,
  removing the tilt the reference shot baked into the whole panorama.
- `PhotoGainSolver`: global per-channel gain compensation solved over equirectangular
  probes, so overlapping photos agree in brightness *and* colour temperature.
- `BandBlender`: two-band blending (wide feather for low frequencies, winner-takes-most
  for detail) — seams stop showing without smearing texture into ghosts.
- `MetalSphereProjector.Options.adaptive()`: output resolution up to 6144×3072 chosen
  from the memory actually available.

### Fixed
- Exposure gain had no effect: it scaled the blend weight as well as the colour, so it
  cancelled out in the normalisation pass.
- `PoleFiller` used two full-resolution scratch textures where one suffices.

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
