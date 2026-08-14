# Graph Report - .  (2026-08-13)

## Corpus Check
- 109 files · ~50,311 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1572 nodes · 3316 edges · 84 communities (81 shown, 3 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 306 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Capture Guide
- Metal Panorama Rendering
- Shared UI Utilities
- Session Stitch Pipeline
- Live Reconstruction
- Node Galaxy Preview
- Camera Preview UI
- Panorama Viewer UI
- Coverage Geometry
- Mesh Walk Viewer
- Capture HUD Components
- Metal Shader Pipeline
- Application Routing
- Room Mesh Storage
- Camera Capture Engine
- Photo Gain Solving
- Capture Sample Coding
- Tour Navigation Model
- Tour Viewer Interface
- Undistortion Shaders
- Glass UI Effects
- Room Scan Workflow
- Hotspot Overlay
- Capture Confidence Collision
- Blend Shaders
- AR Room Scanner
- Band Blending
- Image Storage Logging
- Capture Evaluation
- AR Session Management
- Capture Gate Logic
- Photo Capture Manager
- Project Library Model
- Project Detail Flow
- Photo Capture Delegate
- Pipeline Error Handling
- Pole Fill Shaders
- Mesh Texture Accumulation
- Theme Styling
- Pole Filling
- Crash Reporting
- Capture Sample Model
- Device Pose Projection
- Project Branding
- Tour Link Editing
- Project Persistence
- Router Destinations
- Capture Haptics Progress
- Onboarding Navigation
- Tour Autoplay
- Capture Screen Actions
- Capture Overlay Rendering
- Holographic Background
- Project Detail Interface
- Mesh Vertex Texturing
- Motion Tracking
- Stitch Pipeline Stages
- Automatic Tour Linking
- Live Scanner Interface
- Blur Detection
- Holographic Buttons
- Horizon Leveling
- Capture Lifecycle
- Room Scan Interface
- Application Theme
- Orientation Resolution
- Camera Status
- Stability Estimation
- Tour Scene Model
- Project Library Interface
- Metal Shader Uniforms
- Capture Error Handling
- Lens Calibration
- Circular Progress UI
- Stitch Progress UI
- Stitching Interface
- Sphere Mesh Geometry
- Exposure Compensation
- Metal Stitch Errors
- Image Writer Errors
- Camera Sample Output
- Capture Startup
- Room Scan Completion

## God Nodes (most connected - your core abstractions)
1. `CaptureViewModel` - 56 edges
2. `TourViewerViewModel` - 52 edges
3. `AppRouter` - 38 edges
4. `CaptureSample` - 38 edges
5. `CaptureGuide` - 35 edges
6. `PanoramaSession` - 34 edges
7. `Project` - 33 edges
8. `MetalSphereProjector` - 30 edges
9. `TourViewerView` - 30 edges
10. `CameraEngine` - 29 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `RootView`  [INFERRED]
  App/Panorama360App.swift → UI/RootView.swift
- `.lookDirection` --references--> `simd_quatf`  [INFERRED]
  Domain/DeviceOrientation.swift → Device/Motion/MotionEngine.swift
- `AppRouter` --calls--> `ProjectStore`  [INFERRED]
  App/AppRouter.swift → Utilities/Storage/ProjectStore.swift
- `RoomScanViewModel` --calls--> `MeshTexturizer`  [INFERRED]
  Presentation/RoomScanViewModel.swift → Device/AR/MeshTexturizer.swift
- `RoomScanViewModel` --calls--> `RoomScanner`  [INFERRED]
  Presentation/RoomScanViewModel.swift → Device/AR/RoomScanner.swift

## Import Cycles
- None detected.

## Communities (84 total, 3 thin omitted)

### Community 0 - "Capture Guide"
Cohesion: 0.05
Nodes (51): CaseIterable, Array, .capturedCount, .fractionComplete, .nextUncaptured, CapturePoint, .isCaptured, Bool (+43 more)

### Community 1 - "Metal Panorama Rendering"
Cohesion: 0.05
Nodes (44): MTLLibrary, MTLPixelFormat, MetalSphereProjector, Options, Bool, CGImage, CIContext, CIImage (+36 more)

### Community 2 - "Shared UI Utilities"
Cohesion: 0.06
Nodes (25): ARKit, AVFoundation, Combine, CoreGraphics, CoreImage, CoreImage.CIFilterBuiltins, CoreMotion, Foundation (+17 more)

### Community 3 - "Session Stitch Pipeline"
Cohesion: 0.06
Nodes (29): PanoramaSession, .capturedCount, .fractionComplete, .isStitched, .totalPoints, Bool, Date, Double (+21 more)

### Community 4 - "Live Reconstruction"
Cohesion: 0.08
Nodes (33): LiveExposureTracker, CIContext, Double, Int, URL, LiveReconstructionManager, Bool, CGImage (+25 more)

### Community 5 - "Node Galaxy Preview"
Cohesion: 0.07
Nodes (27): SCNMaterial, SCNNode, SCNVector3, Set, GalaxyHost, NodeGalaxyView, .body, .cov (+19 more)

### Community 6 - "Camera Preview UI"
Cohesion: 0.06
Nodes (36): AnyClass, AVCaptureSession, MTKViewDelegate, CameraPreview, PreviewUIView, .layerClass, .videoPreviewLayer, AVCaptureVideoPreviewLayer (+28 more)

### Community 7 - "Panorama Viewer UI"
Cohesion: 0.07
Nodes (30): Bool, String, URL, ViewerViewModel, FOVPill, .body, HeadingCompass, .body (+22 more)

### Community 8 - "Coverage Geometry"
Cohesion: 0.10
Nodes (24): CGAffineTransform, Cell, CoverageAnalyzer, .capturedCount, .effectiveRadius, .isComplete, Bool, Double (+16 more)

### Community 9 - "Mesh Walk Viewer"
Cohesion: 0.08
Nodes (23): AnchorEntity, Cancellable, Entity, MeshResource, ARView, CGVector, SIMD3, String (+15 more)

### Community 10 - "Capture HUD Components"
Cohesion: 0.08
Nodes (29): Shape, HUDRing, .body, Bool, Color, Double, Int, CornerBrackets (+21 more)

### Community 11 - "Metal Shader Pipeline"
Cohesion: 0.09
Nodes (30): accumulate_fragment(), divide_fragment(), constant, float2, float3, float4, fragment, sample (+22 more)

### Community 12 - "Application Routing"
Cohesion: 0.12
Nodes (10): AppRouter, CaptureContext, Bool, Int, UUID, CGSize, .topBar, .bottomBar (+2 more)

### Community 13 - "Room Mesh Storage"
Cohesion: 0.17
Nodes (16): appendArray(), appendU32(), readArray(), readU32(), RoomMesh, .faceCount, .vertexCount, Data (+8 more)

### Community 14 - "Camera Capture Engine"
Cohesion: 0.12
Nodes (15): AVCapturePhotoSettings, AVCaptureVideoDataOutput, AVCaptureVideoDataOutputSampleBufferDelegate, CameraEngine, configurationFailed, SampleBufferProxy, AVCaptureDevice, AVCapturePhoto (+7 more)

### Community 15 - "Photo Gain Solving"
Cohesion: 0.14
Nodes (17): Options, Pair, PhotoGainSolver, Probe, CGImage, Double, Int, MTKTextureLoader (+9 more)

### Community 16 - "Capture Sample Coding"
Cohesion: 0.08
Nodes (25): CodingKey, CodingKeys, cx, cy, exifOrientation, fx, fy, gx (+17 more)

### Community 17 - "Tour Navigation Model"
Cohesion: 0.16
Nodes (11): CGSize, Double, Int, MTLTexture, Never, Task, URL, UUID (+3 more)

### Community 18 - "Tour Viewer Interface"
Cohesion: 0.13
Nodes (17): CGSize, Color, Gesture, Never, String, Task, UUID, Void (+9 more)

### Community 19 - "Undistortion Shaders"
Cohesion: 0.10
Nodes (22): constant, float2, float4, fragment, sample, sampler, texture2d, uint (+14 more)

### Community 20 - "Glass UI Effects"
Cohesion: 0.13
Nodes (15): GlassPanel, CGFloat, Color, Content, Double, View, View, Shimmer (+7 more)

### Community 21 - "Room Scan Workflow"
Cohesion: 0.16
Nodes (11): RoomScanViewModel, ARView, Int, Never, String, Task, URL, UUID (+3 more)

### Community 22 - "Hotspot Overlay"
Cohesion: 0.13
Nodes (14): Hotspot, Double, String, UUID, Identifiable, ProjectedHotspot, Bool, CGFloat (+6 more)

### Community 23 - "Capture Confidence Collision"
Cohesion: 0.23
Nodes (10): CaptureConfidenceEngine, Float, ClosedRange, Double, .grid, MeshCollider, Bool, Int (+2 more)

### Community 24 - "Blend Shaders"
Cohesion: 0.20
Nodes (19): band_blur(), band_combine(), band_downsample(), BandUniforms, normalizeOut, pad0, texelStep, BandVertexOut (+11 more)

### Community 25 - "AR Room Scanner"
Cohesion: 0.15
Nodes (12): ARAnchor, ARMeshAnchor, MeshPart, RoomScanner, .anchorCount, .isSupported, Bool, Int (+4 more)

### Community 26 - "Band Blending"
Cohesion: 0.23
Nodes (12): BandUniforms, BandBlender, BandUniforms, Int, MTLCommandBuffer, MTLCommandQueue, MTLDevice, MTLFunction (+4 more)

### Community 27 - "Image Storage Logging"
Cohesion: 0.20
Nodes (12): OSLog, Log, ImageWriter, AVCapturePhoto, CGFloat, CGImage, CIContext, CIImage (+4 more)

### Community 28 - "Capture Evaluation"
Cohesion: 0.16
Nodes (15): CaptureViewModel, .canFinish, .ceilingCaptured, .floorCaptured, .includesPoles, .latestSharpness, .usesCoverage, Bool (+7 more)

### Community 29 - "AR Session Management"
Cohesion: 0.14
Nodes (11): ARSession, ARSessionDelegate, ARWorldTrackingConfiguration, ARSessionManager, .currentIntrinsics, ARFrame, Double, SIMD3 (+3 more)

### Community 30 - "Capture Gate Logic"
Cohesion: 0.19
Nodes (13): Blocker, adjustingExposure, adjustingFocus, blurry, cooldown, moving, notAligned, noTarget (+5 more)

### Community 31 - "Photo Capture Manager"
Cohesion: 0.31
Nodes (9): CaptureManager, AVCapturePhoto, CGImage, Data, Int, UIImage, URL, UUID (+1 more)

### Community 32 - "Project Library Model"
Cohesion: 0.18
Nodes (8): Project, Date, String, UUID, ObservableObject, LibraryViewModel, String, UUID

### Community 33 - "Project Detail Flow"
Cohesion: 0.20
Nodes (8): ProjectDetailViewModel, .canStartTour, .meshReady, Bool, String, UUID, .saveRow, .body

### Community 34 - "Photo Capture Delegate"
Cohesion: 0.21
Nodes (12): AVCapturePhotoCaptureDelegate, AVCaptureResolvedPhotoSettings, CheckedContinuation, PhotoCaptureDelegate, AVCapturePhoto, AVCapturePhotoOutput, Error, String (+4 more)

### Community 35 - "Pipeline Error Handling"
Cohesion: 0.12
Nodes (16): CameraError, .errorDescription, noRearCamera, runtimeError, unauthorized, String, MotionError, .errorDescription (+8 more)

### Community 36 - "Pole Fill Shaders"
Cohesion: 0.15
Nodes (15): dilate_fragment(), constant, float4, fragment, sample, texture2d, uint, vertex (+7 more)

### Community 37 - "Mesh Texture Accumulation"
Cohesion: 0.23
Nodes (9): Accumulator, DepthMap, ARFrame, Bool, CVPixelBuffer, Int, SIMD3, YUVPlanes (+1 more)

### Community 38 - "Theme Styling"
Cohesion: 0.18
Nodes (13): LinearGradient, .body, .color, R, CGFloat, Color, String, Theme (+5 more)

### Community 39 - "Pole Filling"
Cohesion: 0.30
Nodes (9): PoleFiller, PoleFillUniforms, Int, MTLCommandBuffer, MTLCommandQueue, MTLDevice, MTLRenderPassDescriptor, MTLRenderPipelineState (+1 more)

### Community 40 - "Crash Reporting"
Cohesion: 0.16
Nodes (8): CInt, Darwin, Int32, NSException, StaticString, CrashReporter, panorama360UncaughtExceptionHandler(), String

### Community 41 - "Capture Sample Model"
Cohesion: 0.24
Nodes (11): Codable, Decoder, CameraIntrinsics, CaptureSample, .gravity, .quaternion, Double, Int (+3 more)

### Community 42 - "Device Pose Projection"
Cohesion: 0.20
Nodes (6): DeviceOrientation, .angularSpeed, .lookDirection, Double, SIMD3, PoseProjectionEngine

### Community 43 - "Project Branding"
Cohesion: 0.22
Nodes (9): BrandingSheet, .body, .defaultSwatch, .fields, .swatchRow, Bool, Color, String (+1 more)

### Community 44 - "Tour Link Editing"
Cohesion: 0.21
Nodes (8): AnyShapeStyle, String, .pageIndicator, String, TourLinkSheet, .body, .iconRow, .targetPicker

### Community 45 - "Project Persistence"
Cohesion: 0.36
Nodes (3): ProjectStore, URL, UUID

### Community 46 - "Router Destinations"
Cohesion: 0.15
Nodes (12): Route, capture, library, meshWalk, onboarding, projectDetail, roomScan, stitching (+4 more)

### Community 48 - "Onboarding Navigation"
Cohesion: 0.26
Nodes (9): Card, OnboardingView, .body, Color, String, RootView, .body, String (+1 more)

### Community 49 - "Tour Autoplay"
Cohesion: 0.24
Nodes (6): AutoPlayCoordinator, Bool, Never, Task, Void, UInt64

### Community 50 - "Capture Screen Actions"
Cohesion: 0.24
Nodes (6): CGSize, CaptureView, .body, .liveGlobePiP, String, .body

### Community 51 - "Capture Overlay Rendering"
Cohesion: 0.38
Nodes (6): CaptureOverlay, .body, CGFloat, CGPoint, Color, GraphicsContext

### Community 52 - "Holographic Background"
Cohesion: 0.29
Nodes (8): HoloBackground, .body, CGFloat, CGPoint, CGSize, Color, Double, GraphicsContext

### Community 53 - "Project Detail Interface"
Cohesion: 0.20
Nodes (9): ProjectDetailView, .bottomBar, .emptyState, SceneRow, .body, Bool, Int, UUID (+1 more)

### Community 54 - "Mesh Vertex Texturing"
Cohesion: 0.22
Nodes (6): ARGeometrySource, MeshTexturizer, SIMD4, simd_float4x4, UInt8, UUID

### Community 55 - "Motion Tracking"
Cohesion: 0.22
Nodes (6): CMDeviceMotion, MotionEngine, .isRunning, Bool, Void, TimeInterval

### Community 56 - "Stitch Pipeline Stages"
Cohesion: 0.20
Nodes (10): StitchStage, blending, exposure, finalizing, loading, .order, projecting, undistorting (+2 more)

### Community 57 - "Automatic Tour Linking"
Cohesion: 0.22
Nodes (5): AutoLinker, Double, String, UUID, .editControls

### Community 58 - "Live Scanner Interface"
Cohesion: 0.22
Nodes (6): LiveScanner3DView, .bottomChrome, .coveragePill, .shutterButton, Bool, String

### Community 59 - "Blur Detection"
Cohesion: 0.28
Nodes (6): Accelerate, CoreVideo, BlurEstimator, CVPixelBuffer, Int, vImage_Buffer

### Community 60 - "Holographic Buttons"
Cohesion: 0.22
Nodes (7): ButtonStyle, Configuration, HoloButton, Bool, CGFloat, Color, View

### Community 61 - "Horizon Leveling"
Cohesion: 0.33
Nodes (4): CMQuaternion, simd_quatf, HorizonLeveler, SIMD3

### Community 62 - "Capture Lifecycle"
Cohesion: 0.31
Nodes (4): .cancelButton, .finishButton, .finishButton, .topBar

### Community 63 - "Room Scan Interface"
Cohesion: 0.25
Nodes (7): RoomScanView, .coverageColor, .coverageMeter, .coveragePill, .statusPill, Color, UUID

### Community 64 - "Application Theme"
Cohesion: 0.25
Nodes (5): Panorama360App, .body, Scene, App, Font

### Community 65 - "Orientation Resolution"
Cohesion: 0.39
Nodes (4): OrientationResolver, Double, SIMD3, simd_float4x4

### Community 66 - "Camera Status"
Cohesion: 0.32
Nodes (6): .currentStatus, CameraStatus, .isSettled, AVCaptureDevice, Bool, Double

### Community 67 - "Stability Estimation"
Cohesion: 0.43
Nodes (4): Stability, StabilityEstimator, Bool, Double

### Community 68 - "Tour Scene Model"
Cohesion: 0.39
Nodes (6): .entryScene, Date, Double, String, UUID, TourScene

### Community 69 - "Project Library Interface"
Cohesion: 0.29
Nodes (6): LibraryView, .body, .emptyState, .topBar, ProjectCard, .body

### Community 70 - "Metal Shader Uniforms"
Cohesion: 0.29
Nodes (5): ProjectorUniforms, SIMD2, SIMD4, simd_float4x4, ViewerUniforms

### Community 71 - "Capture Error Handling"
Cohesion: 0.29
Nodes (7): CaptureError, busy, cameraNoData, .errorDescription, noPhotoOutput, writeFailed, String

### Community 72 - "Lens Calibration"
Cohesion: 0.48
Nodes (4): LensProfile, .isIdentity, LensProfileTable, Bool

### Community 73 - "Circular Progress UI"
Cohesion: 0.43
Nodes (5): CircularProgressView, CGFloat, Color, Double, String

### Community 74 - "Stitch Progress UI"
Cohesion: 0.29
Nodes (6): ProgressView360, .body, .etaLabel, Double, Int, String

### Community 75 - "Stitching Interface"
Cohesion: 0.43
Nodes (4): StitchingView, .body, .stageList, String

### Community 76 - "Sphere Mesh Geometry"
Cohesion: 0.38
Nodes (4): SphereMesh, Data, Int, SIMD3

### Community 77 - "Exposure Compensation"
Cohesion: 0.53
Nodes (4): ExposureCompensator, CIContext, CIImage, URL

### Community 78 - "Metal Stitch Errors"
Cohesion: 0.33
Nodes (6): StitchError, .errorDescription, metalUnavailable, noSamples, renderFailed, String

### Community 79 - "Image Writer Errors"
Cohesion: 0.33
Nodes (6): ImageWriterError, destinationFailed, .errorDescription, finalizeFailed, noData, renderFailed

### Community 80 - "Camera Sample Output"
Cohesion: 0.50
Nodes (3): AVCaptureConnection, AVCaptureOutput, CMSampleBuffer

## Knowledge Gaps
- **151 isolated node(s):** `onboarding`, `library`, `capture`, `stitching`, `world` (+146 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Float` connect `Capture Confidence Collision` to `Capture Guide`, `Metal Panorama Rendering`, `Shared UI Utilities`, `Live Reconstruction`, `Node Galaxy Preview`, `Panorama Viewer UI`, `Coverage Geometry`, `Mesh Walk Viewer`, `Room Mesh Storage`, `Camera Capture Engine`, `Photo Gain Solving`, `Room Scan Workflow`, `AR Room Scanner`, `Band Blending`, `Capture Evaluation`, `Capture Gate Logic`, `Mesh Texture Accumulation`, `Pole Filling`, `Capture Sample Model`, `Device Pose Projection`, `Mesh Vertex Texturing`, `Blur Detection`, `Horizon Leveling`, `Orientation Resolution`, `Camera Status`, `Metal Shader Uniforms`, `Lens Calibration`, `Sphere Mesh Geometry`, `Exposure Compensation`?**
  _High betweenness centrality (0.216) - this node is a cross-community bridge._
- **Why does `CaptureViewModel` connect `Capture Evaluation` to `Capture Guide`, `Shared UI Utilities`, `Session Stitch Pipeline`, `Live Reconstruction`, `Camera Preview UI`, `Coverage Geometry`, `Camera Capture Engine`, `Capture Confidence Collision`, `Capture Gate Logic`, `Photo Capture Manager`, `Project Library Model`, `Device Pose Projection`, `Capture Haptics Progress`, `Capture Screen Actions`, `Motion Tracking`, `Live Scanner Interface`, `Capture Lifecycle`, `Stability Estimation`, `Capture Startup`?**
  _High betweenness centrality (0.150) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Shared UI Utilities` to `Capture Guide`, `Session Stitch Pipeline`, `Application Routing`, `Room Mesh Storage`, `Hotspot Overlay`, `Capture Confidence Collision`, `Image Storage Logging`, `Capture Gate Logic`, `Project Library Model`, `Project Detail Flow`, `Crash Reporting`, `Capture Sample Model`, `Device Pose Projection`, `Tour Autoplay`, `Automatic Tour Linking`, `Horizon Leveling`, `Stability Estimation`, `Tour Scene Model`, `Metal Shader Uniforms`, `Lens Calibration`, `Sphere Mesh Geometry`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Are the 5 inferred relationships involving `CaptureViewModel` (e.g. with `CameraEngine` and `CaptureGate`) actually correct?**
  _`CaptureViewModel` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `TourViewerViewModel` (e.g. with `AutoPlayCoordinator` and `ProjectStore`) actually correct?**
  _`TourViewerViewModel` has 8 INFERRED edges - model-reasoned connections that need verification._
- **What connects `onboarding`, `library`, `capture` to the rest of the system?**
  _151 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Capture Guide` be split into smaller, more focused modules?**
  _Cohesion score 0.05432595573440644 - nodes in this community are weakly interconnected._