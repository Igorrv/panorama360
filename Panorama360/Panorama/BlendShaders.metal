//
//  BlendShaders.metal
//  Two-band blending for the equirectangular panorama. The low band comes from
//  a wide cross-fade (hides exposure and alignment steps), the high band from a
//  winner-takes-most accumulation (keeps one photo's texture, so no ghosting).
//
//  All passes carry coverage in alpha and work on premultiplied colour, so
//  uncovered texels (poles, gaps) never bleed black into the blur.
//

#include <metal_stdlib>

using namespace metal;

struct BandVertexOut {
    float4 position [[position]];
    float2 uv;
};

/// Must match `BandBlender.BlurUniforms` byte-for-byte.
struct BandUniforms {
    float2 texelStep;      // offset between taps, in uv units
    float normalizeOut;    // >0.5 → divide colour by coverage on output
    float pad0;
};

vertex BandVertexOut band_vertex(uint vid [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1, -1), float2( 1, -1), float2(-1,  1),
        float2(-1,  1), float2( 1, -1), float2( 1,  1)
    };
    float2 p = positions[vid];
    BandVertexOut out;
    out.position = float4(p, 0, 1);
    out.uv = (p * 0.5 + 0.5);
    return out;
}

/// Averages a 4×4 grid over the destination texel footprint. Input is a
/// normalised image (alpha = coverage flag); output is premultiplied so the
/// blur can stay linear.
fragment float4 band_downsample(BandVertexOut in [[stage_in]],
                                texture2d<float, access::sample> src [[texture(0)]],
                                constant BandUniforms& uni [[buffer(0)]],
                                sampler samp [[sampler(0)]]) {
    float4 sum = float4(0);
    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            float2 offset = (float2(x, y) - 1.5) * 0.25 * uni.texelStep;
            float4 s = src.sample(samp, in.uv + offset);
            sum += float4(s.rgb * s.a, s.a);
        }
    }
    return sum / 16.0;
}

/// Separable Gaussian, σ = 3 texels, 17 taps. Longitude wraps through the
/// sampler's repeat mode, so there is no seam at ±180°.
fragment float4 band_blur(BandVertexOut in [[stage_in]],
                          texture2d<float, access::sample> src [[texture(0)]],
                          constant BandUniforms& uni [[buffer(0)]],
                          sampler samp [[sampler(0)]]) {
    const float sigma = 3.0;
    float4 sum = float4(0);
    float total = 0;
    for (int i = -8; i <= 8; ++i) {
        float w = exp(-0.5 * float(i * i) / (sigma * sigma));
        sum += w * src.sample(samp, in.uv + float(i) * uni.texelStep);
        total += w;
    }
    float4 blurred = sum / total;
    if (uni.normalizeOut < 0.5) return blurred;
    if (blurred.a <= 1e-4) return float4(0);
    return float4(blurred.rgb / blurred.a, 1.0);
}

/// detail − blur(detail) + blur(broad): the photo's own texture on top of the
/// smoothly cross-faded base.
fragment float4 band_combine(BandVertexOut in [[stage_in]],
                             texture2d<float, access::sample> detail [[texture(0)]],
                             texture2d<float, access::sample> lowBroad [[texture(1)]],
                             texture2d<float, access::sample> lowDetail [[texture(2)]],
                             sampler samp [[sampler(0)]]) {
    float4 d = detail.sample(samp, in.uv);
    if (d.a <= 1e-4) return float4(0);   // uncovered — left for PoleFiller
    float3 base = lowBroad.sample(samp, in.uv).rgb;
    float3 lowFrequency = lowDetail.sample(samp, in.uv).rgb;
    return float4(max(base + (d.rgb - lowFrequency), float3(0)), 1.0);
}
