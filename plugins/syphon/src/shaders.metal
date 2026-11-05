// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// YCbCr/RGB -> BGRA conversion for the Syphon publisher. Compiled at run time
// (embedded into the plugin by CMake as a string), see publisher.m.
// struct Params must match VSNParams in publisher.m.
#include <metal_stdlib>
using namespace metal;

struct Params {
    float4 crop;  // xy origin, zw size of the visible area, normalized to the source texture
    float4 r;     // rgb = (dot(r.xyz, yuv) + r.w, dot(g...), dot(b...))
    float4 g;
    float4 b;
};

struct VOut {
    float4 pos [[position]];
    float2 uv;
};

vertex VOut vsn_vertex(uint vid [[vertex_id]], constant Params &p [[buffer(0)]])
{
    // One triangle covering the whole target; uv (0,0) is the top-left of the visible area.
    float2 t = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.pos = float4(t * 2.0 - 1.0, 0.0, 1.0);
    o.uv = p.crop.xy + float2(t.x, 1.0 - t.y) * p.crop.zw;
    return o;
}

constexpr sampler smp(filter::linear, address::clamp_to_edge);

static float4 yuv_to_rgb(float3 yuv, constant Params &p)
{
    return float4(dot(p.r.xyz, yuv) + p.r.w,
                  dot(p.g.xyz, yuv) + p.g.w,
                  dot(p.b.xyz, yuv) + p.b.w, 1.0);
}

fragment float4 vsn_biplanar(VOut in [[stage_in]], constant Params &p [[buffer(0)]],
                             texture2d<float> y [[texture(0)]], texture2d<float> uv [[texture(1)]])
{
    return yuv_to_rgb(float3(y.sample(smp, in.uv).r, uv.sample(smp, in.uv).rg), p);
}

fragment float4 vsn_planar(VOut in [[stage_in]], constant Params &p [[buffer(0)]],
                           texture2d<float> y [[texture(0)]], texture2d<float> u [[texture(1)]],
                           texture2d<float> v [[texture(2)]])
{
    return yuv_to_rgb(float3(y.sample(smp, in.uv).r, u.sample(smp, in.uv).r,
                             v.sample(smp, in.uv).r), p);
}

fragment float4 vsn_rgb(VOut in [[stage_in]], texture2d<float> rgb [[texture(0)]])
{
    return float4(rgb.sample(smp, in.uv).rgb, 1.0);
}
