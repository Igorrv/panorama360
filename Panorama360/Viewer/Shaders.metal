//
//  Shaders.metal
//  Renders an equirectangular panorama on the inside of a sphere viewed from
//  its centre. The sphere vertices' fixed positions double as the direction
//  used to sample the equirectangular texture.
//

#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

constant float PI = 3.14159265358979323846264338327950288;

struct ViewerVertexOut {
    float4 position [[position]];
    float3 direction;
};

vertex ViewerVertexOut viewer_vertex(uint vid [[vertex_id]],
                                     constant float3 *positions [[buffer(0)]],
                                     constant ViewerUniforms &uni [[buffer(1)]]) {
    float3 pos = positions[vid];
    float3 p = (uni.viewMatrix * float4(pos, 1.0)).xyz;

    float f = 1.0 / tan(uni.fovRadians * 0.5);
    ViewerVertexOut out;
    // Camera at origin looking down −Z. Points in front have p.z < 0 → w > 0.
    out.position = float4(p.x * f / uni.aspect, p.y * f, 0.0, -p.z);
    out.direction = pos; // fixed panorama direction, independent of view rotation
    return out;
}

fragment float4 viewer_fragment(ViewerVertexOut in [[stage_in]],
                                texture2d<float, access::sample> pano [[texture(0)]],
                                sampler samp [[sampler(0)]]) {
    float3 d = normalize(in.direction);
    float lon = atan2(-d.x, -d.z);
    float lat = asin(clamp(d.y, -1.0, 1.0));
    float2 tex = float2((lon / PI + 1.0) * 0.5, 0.5 - lat / PI);
    return pano.sample(samp, tex);
}
