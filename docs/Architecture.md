# Architecture

Panorama360 follows **MVVM + Clean Architecture** with Swift Concurrency (`actor`, `AsyncStream`, `@MainActor`). Hardware engines stay behind narrow interfaces; ViewModels never talk to AVFoundation/ARKit directly.

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│  UI (SwiftUI)                                                │
│  CaptureView · StitchingView · PanoramaViewerView · Overlay │
├─────────────────────────────────────────────────────────────┤
│  Presentation (ViewModels)                                   │
│  CaptureViewModel · StitchingViewModel · ViewerViewModel     │
├─────────────────────────────────────────────────────────────┤
│  App                                                         │
│  Panorama360App · AppRouter (capture → stitching → viewer)   │
├──────────────┬──────────────┬──────────────┬────────────────┤
│ Guide        │ Device       │ Panorama     │ Viewer         │
│ CaptureGuide │ Camera/AR/   │ PanoramaEngine│ ViewerEngine  │
│ SpherePoints │ Motion/Gate  │ MetalProjector│ Metal shaders │
├──────────────┴──────────────┴──────────────┴────────────────┤
│  Domain (pure models, Codable, no frameworks)                │
│  PanoramaSession · CapturePoint · CaptureSample · …          │
└─────────────────────────────────────────────────────────────┘
```

## Navigation flow

`AppRouter` owns a single `Route`:

1. **`.capture`** — live camera + floating sphere points.
2. **`.stitching(session)`** — progress UI while `PanoramaEngine` runs.
3. **`.viewer(url)`** — Metal equirectangular sphere, gyro + drag + pinch.

Cancel from stitching returns to a fresh capture (`captureGeneration` forces ViewModel reset).

## Capture pipeline (hot path)

Every display-link / AR frame tick roughly does:

```
ARSessionManager ──pose──┐
MotionEngine ──stability─┤
CameraEngine ──preview───┼─► CaptureGuide (alignment + overlay points)
BlurEstimator ──sharp───┤
CameraStatus ───────────┘
         │
         ▼
   CaptureGate.evaluate()  → ready? → CaptureManager.fire()
         │                              │
         │                              ▼
         │                     CaptureSample (JPEG + quaternion + intrinsics)
         │                              │
         └──────────────────────────────┴─► SessionStore (disk)
```

### CaptureGate thresholds (defaults)

| Condition | Default | Blocker |
|-----------|---------|---------|
| Angular distance to target | ≤ 4.5° | `notAligned` |
| Stability score | ≥ 0.72 | `moving` |
| Focus settled | required | `adjustingFocus` |
| Exposure settled | required | `adjustingExposure` |
| Laplacian variance | ≥ 25 | `blurry` |
| Cooldown after shot | must elapse | `cooldown` |

All knobs live on `CaptureGate` — tune without touching UI.

## Stitching pipeline

`PanoramaEngine` (actor) serializes GPU/disk work:

```
samples[] → HorizonLeveler (gravity → level horizon)
         → PhotoGainSolver (global exposure + white balance)
         → Undistorter (Brown–Conrady, ultra-wide only; identity otherwise)
         → MetalSphereProjector (warp + accumulate two bands)
         → BandBlender (low band from the wide band, detail from the sharp one)
         → PoleFiller (dilate colour into uncovered gaps)
         → ImageWriter → session equirectangular URL
```

Because ARKit recorded the **exact orientation** of each shot, warping is deterministic — no blind feature matching. Optional `OpenCVStitcher` swaps in via `#if canImport(opencv2)` (see [OpenCVIntegration.md](OpenCVIntegration.md)).

### What each quality stage fixes

| Stage | Artefact it removes | How |
| --- | --- | --- |
| `HorizonLeveler` | Horizon drawn as a sine wave | Averages the per-shot gravity vector to find true "up" in the reference frame, then pre-rotates every quaternion. Skipped when tilt is unmeasurable, < 0.3°, or > 30°. |
| `PhotoGainSolver` | Patchwork brightness and colour cast | Projects every photo into a 128×64 equirect probe, so overlapping photos share pixel coordinates and their means are directly comparable. Solves all pairwise constraints (Gauss–Seidel on log gains, per channel) for one RGB gain per photo. |
| `BandBlender` | Exposure steps *and* ghosting at seams | Two accumulations: a wide feather (smooth transitions) and a sharp, high-exponent weight (one photo wins each pixel). Result is `blur(wide) + (sharp − blur(sharp))`, blurred at 1/8 scale with longitude wrap. |
| `PoleFiller` | Black holes at the poles | Morphological dilation, ping-ponging between the target and a single scratch texture. |

`Options.adaptive()` sizes the output (up to 6144×3072) from `os_proc_available_memory()`; peak use is ~4 full-res RGBA16F textures, and each accumulator is released the moment it is normalised. Kill-switches: `PANORAMA_DISABLE_GAINSOLVE`, `PANORAMA_DISABLE_TWOBAND`, `PANORAMA_DISABLE_UNDISTORT`, `PANORAMA_POLEFILL_ITERS=0`.

## Viewer pipeline

```
equirect JPEG → MTKTexture → SphereMesh + Shaders.metal
             → PanoramaRenderer (MTKViewDelegate)
             → ViewerEngine (drag / pinch / CoreMotion tilt)
```

## Concurrency rules

- **UI / ViewModels:** `@MainActor`.
- **CaptureManager / PanoramaEngine:** `actor` — one capture or stitch at a time.
- **Hardware engines:** own their queues; publish via `AsyncStream` or `@Published` bridged to MainActor.
- Domain types are `Sendable` / `Codable` so they cross actor boundaries safely.

## Why no backend in v1

Feed, auth, marketplace, tokens, AI, and cloud sync are **out of scope**. Module boundaries (`SessionStore`, `PanoramaSession`, stitcher protocol) are left clean so those features can plug in later without rewriting capture or Metal.
