---
type: "query"
date: "2026-08-13T04:00:00.224853+00:00"
question: "continue melhorias no projeto para escanear o ambiente e virar uma imagem 360º graus navegavel"
contributor: "graphify"
outcome: "useful"
source_nodes: ["CaptureViewModel", "CaptureGuide", "PanoramaSession", "SessionStore", "PanoramaEngine"]
---

# Q: continue melhorias no projeto para escanear o ambiente e virar uma imagem 360º graus navegavel

## Answer

Expanded from original query via graph vocab: [capture, coverage, panorama, stitch, viewer, project, session, tour, hotspot, orientation, motion, camera]. The traversal identified CaptureViewModel, CaptureGuide, PanoramaSession, SessionStore and PanoramaEngine as the critical capture-to-viewer path. Verification found mismatched session/directory UUIDs, capture hardware left running on automatic completion, dynamic capture count stuck at one, and the stitched URL not persisted. Those invariants were corrected.

## Outcome

- Signal: useful

## Source Nodes

- CaptureViewModel
- CaptureGuide
- PanoramaSession
- SessionStore
- PanoramaEngine