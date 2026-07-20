//
//  PoleFillShaders.metal
//  Morphological dilation that fills uncovered gaps (poles, thin seams) in the
//  final equirectangular texture. `divide_fragment` writes alpha == 0 where no
//  capture landed; each dilation pass copies the nearest covered texel into its
//  alpha==0 neighbours, shrinking the hole boundary. Self-contained vertex
//  (does not reuse `quad_vertex` to avoid cross-file struct assumptions).
//
//  The fragment reads texels with `.read()` (point-sampled, integer coords) so a
//  covered neighbour is copied verbatim — no half-brightness blending a covered
//  texel against an uncovered one the way a linear sampler would.
//

#include <metal_stdlib>
using namespace metal;

struct PoleFillVertOut {
    float4 position [[position]];
};

vertex PoleFillVertOut polefill_vertex(uint vid [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1, -1), float2( 1, -1), float2(-1,  1),
        float2(-1,  1), float2( 1, -1), float2( 1,  1)
    };
    PoleFillVertOut out;
    out.position = float4(positions[vid], 0, 1);
    return out;
}

struct PoleFillUniforms {
    float stepPixels;   // neighbour offset for this pass (caller doubles it)
    float pad0, pad1, pad2;
};

/// For each pixel: if already covered (alpha > 0.5), keep its colour opaque.
/// Otherwise search the 8 neighbours at ±stepPixels and adopt the first covered
/// neighbour's colour. If none is covered, leave it uncovered for the next pass.
fragment float4 dilate_fragment(PoleFillVertOut in [[stage_in]],
                                texture2d<float, access::sample> src [[texture(0)]],
                                constant PoleFillUniforms& uni [[buffer(0)]]) {
    uint2 size = uint2(src.get_width(), src.get_height());
    int2 px = int2(in.position.xy);
    int2 c = clamp(px, int2(0), int2(size) - 1);

    float4 center = src.read(uint2(c));
    if (center.a > 0.5) return float4(center.rgb, 1.0);

    int s = int(uni.stepPixels + 0.5);
    const int2 offsets[8] = {
        int2( s,  0), int2(-s,  0), int2( 0,  s), int2( 0, -s),
        int2( s,  s), int2(-s,  s), int2( s, -s), int2(-s, -s)
    };
    for (int i = 0; i < 8; ++i) {
        int2 q = c + offsets[i];
        if (q.x < 0 || q.x >= int(size.x) || q.y < 0 || q.y >= int(size.y)) continue;
        float4 n = src.read(uint2(q));
        if (n.a > 0.5) return float4(n.rgb, 1.0);
    }
    return float4(0, 0, 0, 0);   // still uncovered
}
