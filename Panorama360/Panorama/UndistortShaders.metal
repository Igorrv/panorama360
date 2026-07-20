//
//  UndistortShaders.metal
//  Inverse-map lens undistortion: renders a rectilinear copy of a captured
//  photo by sampling the distorted source at the coordinate the lens actually
//  placed each ray at (Brown–Conrady forward model on the sampling coord — no
//  iterative solver). k1=k2=k3=0 is a plain copy, byte-compatible with loading
//  the raw photo.
//
//  Self-contained vertex (does not reuse `quad_vertex` from PanoramaShaders.metal
//  to avoid any cross-file symbol/linker assumption).
//

#include <metal_stdlib>
using namespace metal;

struct UndistortVertOut {
    float4 position [[position]];
    float2 uv;
};

vertex UndistortVertOut undistort_vertex(uint vid [[vertex_id]]) {
    // Two triangles covering clip space.
    float2 positions[6] = {
        float2(-1, -1), float2( 1, -1), float2(-1,  1),
        float2(-1,  1), float2( 1, -1), float2( 1,  1)
    };
    float2 p = positions[vid];
    UndistortVertOut out;
    out.position = float4(p, 0, 1);
    out.uv = (p * 0.5 + 0.5);              // [0,1], origin bottom-left
    return out;
}

struct UndistortUniforms {
    float fx, fy, cx, cy;   // photo pixel-space intrinsics
    float k1, k2, k3;       // Brown–Conrady radial coefficients
    float pad;
};

/// For each output pixel, convert its stitcher-space texture coord into photo
/// pixel space, apply the forward distortion to find where the lens placed that
/// ray, and sample the source there. The `t.y = 1 - in.uv.y` flip maps the
/// quad's bottom-left origin onto the stitcher's top-left (topLeft load)
/// convention so the result is a drop-in replacement for the raw photo texture.
fragment float4 undistort_fragment(UndistortVertOut in [[stage_in]],
                                   texture2d<float, access::sample> src [[texture(0)]],
                                   constant UndistortUniforms& uni [[buffer(0)]],
                                   sampler samp [[sampler(0)]]) {
    float2 t = float2(in.uv.x, 1.0 - in.uv.y);
    float2 size = float2(src.get_width(), src.get_height());

    float u = t.x * size.x;
    float v = t.y * size.y;
    float xn = (u - uni.cx) / uni.fx;
    float yn = (v - uni.cy) / uni.fy;
    float r2 = xn * xn + yn * yn;
    float r4 = r2 * r2;
    float r6 = r4 * r2;
    float dist = 1.0 + uni.k1 * r2 + uni.k2 * r4 + uni.k3 * r6;

    float du = uni.fx * (xn * dist) + uni.cx;
    float dv = uni.fy * (yn * dist) + uni.cy;
    float2 dt = float2(du / size.x, dv / size.y);

    return src.sample(samp, dt);
}
