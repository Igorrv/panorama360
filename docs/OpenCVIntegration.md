# Optional: add OpenCV for richer stitching

The default build stitches with the **pure-Apple** `MetalSphereProjector`, which
uses each shot's known ARKit/CoreMotion orientation to warp photos directly onto
the equirectangular sphere. No third-party dependencies, compiles instantly.

If you want feature-based bundle adjustment + multi-band seam blending on top,
add OpenCV and the existing `OpenCVStitcher` activates automatically.

## 1. Get the OpenCV iOS framework

Download the official iOS pack from <https://opencv.org/releases/> (e.g.
`opencv-4.x-ios-framework.zip`), which contains `opencv2.xcframework`.

> Or build from source with `-DBUILD_opencv_world=ON` for a smaller footprint.

## 2. Add it to the Xcode project

After `xcodegen generate`, open `Panorama360.xcodeproj`:

1. Select the **Panorama360** target → **General** → **Frameworks, Libraries, and Embedded Content**.
2. `+` → **Add Other...** → **Add Files...** → choose `opencv2.xcframework`.
3. Ensure **Embed & Sign** is selected.
4. Build Settings → **Framework Search Paths** includes the folder containing the xcframework.

## 3. (Re)generate the project so XcodeGen tracks it

To make the dependency permanent, add it to `project.yml`:

```yaml
targets:
  Panorama360:
    dependencies:
      - framework: path/to/opencv2.xcframework
        embed: true
```

Then `xcodegen generate` again.

## 4. Use the OpenCV stitcher

`Panorama/OpenCV/OpenCVStitcher.swift` is guarded by `#if canImport(opencv2)`,
so once the framework is linked it compiles. Swap the stitcher in
`Panorama/PanoramaEngine.swift` (or in `StitchingViewModel.run`):

```swift
let engine = PanoramaEngine(stitcher: OpenCVStitcher(), store: store)
```

Then implement the body of `OpenCVStitcher.stitch(...)`:

1. Load each `CaptureSample` into a `cv::Mat` (use `cv::imread` on the HEIC path,
   or bridge a `CGImage` → `Mat`). Optionally undistort with the sample's
   `intrinsics` (`cv::undistort`).
2. Build a `std::vector<cv::Mat>` and a `std::vector<cv::detail::CameraParams>`
   seeded with each shot's quaternion (convert `simd_quatf` → a rotation matrix
   and then to Rodrigues for `CameraParams.R`). Seeding orientation lets
   `cv::Stitcher` skip most of the matching.
3. `auto stitcher = cv::Stitcher::create(cv::Stitcher::SCANS);`
   `stitcher->stitch(images, rois, pano);`
4. Encode `pano` to HEIC/PNG and write to `outputURL`.
5. Report `onProgress(fraction, stage)` between stages.

## 5. C++ bridging

OpenCV is C++. From Swift, expose a small Objective-C++ wrapper
(`opencv-wrapper.mm`) with a pure-C/Obj-C interface, then call it from
`OpenCVStitcher` via the bridging header. Keep `simd` ↔ `cv::Mat` conversions in
that wrapper.

## Notes

- The pure-Apple projector is usually **more reliable** for guided captures
  because orientation is already exact; OpenCV shines for blind/unordered sets
  or for premium seam blending. Consider offering both and letting the result
  with better coverage win.
- OpenCV roughly adds 40–60 MB to the app binary.
