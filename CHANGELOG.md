# Changelog

## [1.3.0] — 2026-08-14

### Fixed
- **Focal length was ~33% short.** It was derived from the portrait photo's *width*,
  but `videoFieldOfView` measures the sensor's long axis (the image *height* once
  stored upright). Every photo was projected onto far more sphere than it covered,
  so neighbouring shots could not line up no matter how good the blending was.
- **Photo orientation is now baked into the pixels.** Setting the capture connection
  to portrait does not guarantee rotated pixels — AVFoundation may describe the
  rotation in EXIF instead, which the stitcher ignores. Captures could therefore land
  in the sphere rotated 90°.
- **Panoramas came out dark, twice over.** The pipeline blends in linear light, but
  the result was written as if it were already gamma-encoded, and the in-app viewer
  drew linear values into a non-sRGB drawable. Colour is now explicit end to end.
- **Stills were captured from a 16:9 video format.** Without `sessionPreset = .photo`
  the session defaulted to `.high`: photos came back cropped top and bottom (fewer
  degrees per shot ⇒ holes in the sphere) and below the sensor's resolution.
- Guide overlay used the sensor's landscape FOV as the screen's, so target dots sat
  off to the side of the object they marked.

### Changed
- Sharpness sampling throttled to ~12 Hz (was every preview frame) and the unused
  `latestPixelBuffer` removed, which was pinning a buffer from the capture pool.
- Coverage now credits each shot with its narrow half-FOV instead of the wide one.
- Lens undistortion renders to sRGB storage instead of packing linear light into
  8-bit unorm (which banded the shadows).

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
