//
//  ShaderTypes.h
//  Shared structs between the Metal shaders (which #include this header) and
//  Swift (which uses the byte-identical duplicates in ShaderUniforms.swift).
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// MARK: - 360° Viewer (equirectangular sphere)

typedef struct {
    matrix_float4x4 viewMatrix;   // camera rotation (look) matrix
    float fovRadians;
    float aspect;                 // viewport width / height
    float pad[2];
} ViewerUniforms;

// MARK: - Panorama projector (photo → equirectangular)

typedef struct {
    vector_float4 quaternion;     // relative orientation (x, y, z, w) — start frame → photo
    vector_float4 intrinsics;     // fx, fy, cx, cy (photo pixel space)
    vector_float2 imageSize;      // photo width, height (pixels)
    vector_float2 outputSize;     // equirect width, height (pixels)
    vector_float4 gain;           // rgb: per-channel exposure gain; w: blend weight exponent
    float feather;                // 0..1 — feather *width* at the FOV edge
    float pad[3];
} ProjectorUniforms;

#endif /* ShaderTypes_h */
