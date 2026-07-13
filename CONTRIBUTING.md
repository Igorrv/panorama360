# Contributing

## Scope of this repo

v1 is **capture + stitch + viewer** only. PRs that add auth, social feed, marketplace, tokens, or cloud backends should wait until those modules are intentionally scoped — or be discussed in an Issue first.

## Local setup

See [BuildingOnMac.md](docs/BuildingOnMac.md). Windows contributors: use the CI IPA path in [InstallingOnWindows.md](docs/InstallingOnWindows.md) to test on device.

## Code style

- Swift 5.9+, iOS 16 APIs only.
- Prefer `actor` / `@MainActor` / `Sendable` over ad-hoc queues.
- Keep files under ~400 lines; split rather than grow god-objects.
- Domain models stay free of UIKit / AVFoundation / Metal.
- No force-unwraps in production paths; surface errors to the ViewModel.

## Architecture rules

1. ViewModels talk to engines/guides — not to `AVCaptureSession` directly.
2. New stitchers implement `PanoramaStitcher` and plug into `PanoramaEngine`.
3. Tunable capture behavior goes on `CaptureGate` / `AlignmentThresholds`, not magic numbers in views.
4. Regenerate Xcode via `xcodegen generate`; don't commit `.xcodeproj`.

## PR checklist

- [ ] Builds on device (or CI `Build IPA` is green).
- [ ] No secrets / certificates / provisioning profiles committed.
- [ ] Docs updated if you change the pipeline or install path.
- [ ] Portuguese or English docs are fine; keep README links accurate.

## Commit messages

Prefer [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(capture): tighten stability gate for low light
fix(viewer): reset gyro bias after pinch
docs: explain CaptureGate blockers in Architecture.md
```
