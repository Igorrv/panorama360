//
//  PanoramaShaders.metal
//  Warps each captured photo onto an equirectangular canvas by its known
//  orientation, accumulating a weighted average so seams blend.
//

#include <metal_stdlib>
#include "../Viewer/ShaderTypes.h"

using namespace metal;

constant float PI = 3.14159265358979323846264338327950288;

// MARK: - Full-screen quad vertex

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut quad_vertex(uint vid [[vertex_id]]) {
    // Two triangles covering clip space.
    float2 positions[6] = {
        float2(-1, -1), float2( 1, -1), float2(-1,  1),
        float2(-1,  1), float2( 1, -1), float2( 1,  1)
    };
    float2 p = positions[vid];
    VertexOut out;
    out.position = float4(p, 0, 1);
    out.uv = (p * 0.5 + 0.5);              // [0,1], origin bottom-left
    return out;
}

// MARK: - Helpers

// Rotate vector v by unit quaternion q.
inline float3 qrot(float4 q, float3 v) {
    float3 t = 2.0 * cross(q.xyz, v);
    return v + q.w * t + cross(q.xyz, t);
}

// (pitch, yaw) → unit vector in the session start frame
// (0, 0) → (0, 0, -1)
inline float3 sphere_dir(float pitch, float yaw) {
    float cp = cos(pitch);
    return float3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp);
}

// MARK: - Accumulate fragment (one photo → weighted sum into RGBA16f accumulator)

fragment float4 accumulate_fragment(VertexOut in [[stage_in]],
                                    texture2d<float, access::sample> photo [[texture(0)]],
                                    constant ProjectorUniforms& uni [[buffer(0)]],
                                    sampler samp [[sampler(0)]]) {
    // Output pixel → longitude / latitude.
    float lon = (in.uv.x) * 2.0 * PI - PI;        // -π .. π
    float lat = (0.5 - in.uv.y) * PI;             // +π/2 (top) .. -π/2 (bottom)
    float3 dir = sphere_dir(lat, lon);

    // Rotate the sphere (start-frame) direction into this photo's device frame.
    float4 qInv = float4(-uni.quaternion.xyz, uni.quaternion.w); // conjugate of unit quat
    float3 dCam = qrot(qInv, dir);

    // Camera forward is -Z; discard anything behind the lens.
    float depth = -dCam.z;
    if (depth <= 1e-3) discard_fragment();

    // Pinhole projection (photo pixel space). Image y points down.
    float fx = uni.intrinsics.x, fy = uni.intrinsics.y;
    float cx = uni.intrinsics.z, cy = uni.intrinsics.w;
    float u = fx * (dCam.x / depth) + cx;
    float v = -fy * (dCam.y / depth) + cy;

    float2 size = uni.imageSize;
    // Outside the photo: contribute nothing.
    if (u < 0 || u > size.x || v < 0 || v > size.y) discard_fragment();

    float2 tex = float2(u / size.x, v / size.y);
    float4 color = photo.sample(samp, tex);

    // Weight: cosine foreshortening (falls off toward the lens edge) with a soft
    // feather, times exposure gain. A zero alpha photo pixel contributes nothing.
    float3 n = normalize(dCam);
    float cosine = saturate(-n.z);
    // Feather close to the image border so photos cross-fade.
    float edgeU = 1.0 - smoothstep(0.45, 0.5, fabs(tex.x - 0.5));
    float edgeV = 1.0 - smoothstep(0.45, 0.5, fabs(tex.y - 0.5));
    float feather = mix(1.0, edgeU * edgeV, uni.feather);
    float weight = cosine * feather * uni.exposureGain;

    return float4(color.rgb * weight, weight);
}

// MARK: - Divide fragment (weighted average → final equirectangular)

fragment float4 divide_fragment(VertexOut in [[stage_in]],
                                texture2d<float, access::sample> accum [[texture(0)]],
                                sampler samp [[sampler(0)]]) {
    float4 acc = accum.sample(samp, in.uv);
    if (acc.a <= 1e-4) return float4(0, 0, 0, 1);   // uncovered area → black
    return float4(acc.rgb / acc.a, 1.0);
}
