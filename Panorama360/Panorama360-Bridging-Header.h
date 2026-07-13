//
//  Panorama360-Bridging-Header.h
//
//  Intentionally empty. Swift↔Metal uniform structs are duplicated:
//  - Metal uses Viewer/ShaderTypes.h (its own compile).
//  - Swift uses Viewer/ShaderUniforms.swift (identical memory layout).
//  They are passed byte-for-byte, so the layouts must stay in sync.
//

#ifndef PANORAMA360_BRIDGING_HEADER_H
#define PANORAMA360_BRIDGING_HEADER_H

#endif
