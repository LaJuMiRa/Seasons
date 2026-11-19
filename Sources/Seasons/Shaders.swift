// Metal shader source, compiled at runtime with `MTLDevice.makeLibrary(source:)`.
// This keeps the build free of the `metal` compiler, which the Command Line Tools do not ship.
// All shapes are procedural (signed distance functions); there are no image assets.

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Sprite {
    float2 pos;
    float2 size;
    float rotation;
    float shape;
    float param;
    float param2;
    float4 color;
};

// Packed: matches the 24-byte Swift struct (float4 would otherwise be 16-byte aligned).
struct PileVertex {
    packed_float2 pos;
    packed_float4 color;
};

struct Uniforms {
    float2 viewSize;
    float2 pad;
};

struct SpriteOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float shape;
    float param;
    float param2;
};

struct PileOut {
    float4 position [[position]];
    float4 color;
};

constant float2 corners[6] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(-1,1), float2(1,-1), float2(1,1) };
constant float pad = 1.18;

static float4 toClip(float2 p, float2 viewSize) {
    float2 ndc = p / viewSize * 2.0 - 1.0;
    return float4(ndc, 0.0, 1.0);
}

vertex SpriteOut sprite_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                               const device Sprite* sprites [[buffer(0)]],
                               constant Uniforms& u [[buffer(1)]]) {
    Sprite s = sprites[iid];
    float2 c = corners[vid] * pad;
    float2 local = c * s.size * 0.5;
    float cs = cos(s.rotation);
    float sn = sin(s.rotation);
    float2 world = s.pos + float2(local.x * cs - local.y * sn, local.x * sn + local.y * cs);
    SpriteOut o;
    o.position = toClip(world, u.viewSize);
    o.uv = c;
    o.color = s.color;
    o.shape = s.shape;
    o.param = s.param;
    o.param2 = s.param2;
    return o;
}

vertex PileOut pile_vertex(uint vid [[vertex_id]], const device PileVertex* verts [[buffer(0)]],
                           constant Uniforms& u [[buffer(1)]]) {
    PileOut o;
    o.position = toClip(float2(verts[vid].pos), u.viewSize);
    o.color = float4(verts[vid].color);
    return o;
}

fragment float4 pile_fragment(PileOut in [[stage_in]]) {
    return float4(in.color.rgb * in.color.a, in.color.a);
}

// Anti-aliased coverage of a signed distance (negative = inside).
static float cover(float d) {
    float w = max(fwidth(d), 1e-4);
    return 1.0 - smoothstep(-w, w, d);
}

static float4 flake(float2 uv) {
    float r = length(uv);
    float core = smoothstep(1.0, 0.3, r);
    return float4(1.0, 1.0, 1.0, core);
}

static float4 leaf(float2 uv, float variant, float3 base) {
    float d;
    if (variant > 0.5 && variant < 1.5) {
        // Lobed (maple-like) leaf: polar radius modulation.
        float2 p = uv - float2(0.0, -0.1);
        float a = atan2(p.x, p.y);
        float lobes = 0.62 + 0.22 * cos(a * 5.0) + 0.08 * cos(a * 15.0);
        lobes *= 1.0 - 0.25 * smoothstep(2.2, 3.1, abs(a));
        d = length(p) - lobes;
    } else {
        // Almond leaf with a pointed tip.
        float y = clamp(uv.y, -1.0, 1.0);
        float half_w = 0.55 * pow(max(1.0 - y * y, 0.0), 0.85) * (1.0 - 0.15 * y);
        d = max(abs(uv.x) - half_w, abs(uv.y) - 0.98);
    }
    // Short stem at the bottom.
    float stem = max(abs(uv.x) - 0.05, abs(uv.y + 1.0) - 0.12);
    float a = max(cover(d), cover(stem));
    float rib = exp(-abs(uv.x) * 28.0) * step(uv.y, 0.85) * 0.35;
    float veins = 0.12 * smoothstep(0.7, 1.0, sin((uv.y - abs(uv.x) * 1.4) * 14.0));
    float light = 0.82 + 0.25 * (uv.y * 0.5 + 0.5) - 0.12 * uv.x;
    float3 col = base * (light - rib - veins);
    return float4(col, a);
}

static float4 streak(float2 uv) {
    float across = smoothstep(1.0, 0.2, abs(uv.x));
    float along = smoothstep(1.0, -0.7, uv.y) * smoothstep(-1.1, -0.85, uv.y);
    return float4(1.0, 1.0, 1.0, across * along);
}

static float4 petal(float2 uv, float3 base) {
    float2 p = uv;
    float widen = 1.38 - 0.32 * p.y;
    float body = length(float2(p.x * widen, p.y * 1.02)) - 0.92;
    float notch = length(p - float2(0.0, 1.0)) - 0.26;
    float d = max(body, -notch);
    float a = cover(d);
    float3 col = mix(base * 0.93, float3(1.0, 0.97, 0.98), 0.45 * smoothstep(0.9, -0.6, p.y));
    col = mix(col, base * 0.8, 0.25 * smoothstep(-0.2, -1.0, p.y));
    return float4(col, a);
}

static float4 bead(float2 uv, float3 base) {
    float r = length(uv);
    float body = cover(r - 0.95);
    float rim = 0.3 + 0.55 * smoothstep(0.35, 0.95, r);
    float hi = smoothstep(0.32, 0.0, length(uv - float2(-0.32, 0.38)));
    float3 col = mix(base, float3(1.0), hi);
    return float4(col, max(body * rim, hi * body));
}

static float4 splash(float2 uv) {
    float r = length(uv);
    return float4(1.0, 1.0, 1.0, smoothstep(1.0, 0.4, r));
}

static float4 stem(float2 uv, float3 base) {
    float a = cover(abs(uv.x) - 0.85);
    float3 col = base * (0.85 + 0.3 * (0.5 - uv.x * 0.5));
    return float4(col, a);
}

static float4 flowerHead(float2 uv, float style, float bloom, float3 base) {
    float r = length(uv);
    float ang = atan2(uv.y, uv.x);
    float3 green = float3(0.36, 0.62, 0.25);
    float3 col = base;
    float a = 0.0;
    if (style < 0.5) {
        // Daisy: many narrow petals and a yellow center.
        float petals = 0.55 + 0.42 * pow(abs(cos(ang * 6.0)), 0.55);
        a = cover(r - petals * 0.95);
        float center = cover(r - 0.3);
        col = mix(base * (0.92 + 0.08 * r), float3(1.0, 0.78, 0.15), center);
        col *= 1.0 - 0.15 * center * smoothstep(0.0, 0.3, r);
    } else if (style < 1.5) {
        // Tulip: rounded cup with three pointed tips.
        float2 p = uv;
        float cup = length(float2(p.x * 1.25, (p.y + 0.15) * 1.05)) - 0.78;
        float topEdge = p.y - (0.45 + 0.28 * pow(abs(cos(p.x * 4.1)), 3.0));
        a = cover(max(cup, topEdge));
        float lines = exp(-pow((abs(p.x) - 0.3) * 10.0, 2.0)) * 0.18;
        col = base * (0.9 + 0.2 * (p.y * 0.5 + 0.5) - lines);
    } else if (style < 2.5) {
        // Poppy: five broad petals, dark center.
        float petals = 0.8 + 0.18 * cos(ang * 5.0);
        a = cover(r - petals * 0.95);
        float center = cover(r - 0.22);
        col = mix(base * (0.8 + 0.25 * r), float3(0.12, 0.08, 0.1), center);
    } else if (style < 3.5) {
        // Star-like five petals (forget-me-not) with a yellow eye.
        float petals = 0.55 + 0.42 * pow(abs(cos(ang * 2.5)), 1.4);
        a = cover(r - petals * 0.95);
        float eye = cover(r - 0.18);
        col = mix(base * (0.9 + 0.15 * r), float3(1.0, 0.85, 0.3), eye);
    } else {
        // Bell: hanging cup with a scalloped rim.
        float2 p = uv;
        float widthAtY = 0.32 + 0.38 * smoothstep(0.7, -0.6, p.y);
        float rim = -0.72 + 0.07 * cos(p.x * 18.0);
        float d = max(abs(p.x) - widthAtY, max(rim - p.y, p.y - 0.75));
        a = cover(d);
        col = base * (0.85 + 0.25 * (1.0 - abs(p.x)));
    }
    // Closed buds are green and small; they colour up while opening.
    col = mix(green, col, smoothstep(0.0, 0.7, bloom));
    return float4(col, a);
}

fragment float4 sprite_fragment(SpriteOut in [[stage_in]]) {
    float2 uv = in.uv;
    float3 base = in.color.rgb;
    float4 s;
    int shape = int(in.shape + 0.5);
    switch (shape) {
        case 0: s = flake(uv); s.rgb = base; break;
        case 1: s = leaf(uv, in.param, base); break;
        case 2: s = streak(uv); s.rgb = base; break;
        case 3: s = petal(uv, base); break;
        case 4: s = bead(uv, base); break;
        case 5: s = splash(uv); s.rgb = base; break;
        case 6: s = stem(uv, base); break;
        default: s = flowerHead(uv, in.param, in.param2, base); break;
    }
    float alpha = clamp(s.a * in.color.a, 0.0, 1.0);
    if (alpha < 0.002) discard_fragment();
    return float4(s.rgb * alpha, alpha);
}
"""
