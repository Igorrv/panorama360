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
samples[] → LensUndistortion → ExposureCompensator
         → MetalSphereProjector (warp + blend onto equirect)
         → ImageWriter → session equirectangular URL
```

Because ARKit recorded the **exact orientation** of each shot, warping is deterministic — no blind feature matching. Optional `OpenCVStitcher` swaps in via `#if canImport(opencv2)` (see [OpenCVIntegration.md](OpenCVIntegration.md)).

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
