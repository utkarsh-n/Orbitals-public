#include <metal_stdlib>
using namespace metal;

struct Segment {
    float2 start;
    float2 end;
    float4 color;
    float4 style;
    float4 detail;
};

struct Uniforms {
    float4 viewport;
    float4 appearance;
};

struct Raster {
    float4 position [[position]];
    float2 point;
    float2 start [[flat]];
    float2 end [[flat]];
    float4 color [[flat]];
    float4 style [[flat]];
    float4 detail [[flat]];
};

vertex Raster phosphorVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device Segment *segments [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    const Segment segment = segments[instanceID];
    const float2 corners[] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(0, 1), float2(1, 0), float2(1, 1)
    };
    float2 delta = segment.end - segment.start;
    float lineLength = length(delta);
    float2 tangent = lineLength > 0.0001 ? delta / lineLength : float2(1, 0);
    float2 normal = float2(-tangent.y, tangent.x);
    float glowRadius = segment.style.y > 0 ? 3 + 7 * segment.style.y : 0;
    float padding = segment.style.x + glowRadius + 1.5;
    float2 corner = corners[vertexID];
    float2 point = segment.start + tangent * mix(-padding, lineLength + padding, corner.x)
                  + normal * mix(-padding, padding, corner.y);
    Raster out;
    out.position = float4(point.x / uniforms.viewport.x * 2 - 1,
                          1 - point.y / uniforms.viewport.y * 2, 0, 1);
    out.point = point;
    out.start = segment.start;
    out.end = segment.end;
    out.color = segment.color;
    out.style = segment.style;
    out.detail = segment.detail;
    return out;
}

fragment half4 phosphorFragment(Raster in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]]) {
    float2 delta = in.end - in.start;
    float lengthSquared = dot(delta, delta);
    float t = lengthSquared > 0.0001 ? clamp(dot(in.point - in.start, delta) / lengthSquared, 0.0, 1.0) : 0;
    float distance = length(in.point - (in.start + t * delta));
    float edge = max(0.5 / uniforms.viewport.z, fwidth(distance) * 0.6);
    float radius = in.style.x;
    float core = 1 - smoothstep(radius - edge, radius + edge, distance);
    if (in.detail.x > 0) {
        core *= smoothstep(in.detail.x - edge, in.detail.x + edge, distance);
    }
    float outside = max(0.0, distance - radius);
    float spread = 1.4 + in.style.y * 3.1;
    float glow = exp(-outside * outside / (spread * spread)) * in.style.y * 0.34;
    if (in.detail.x > 0 && distance < in.detail.x) {
        glow *= smoothstep(max(0.0, in.detail.x - 2), in.detail.x, distance);
    }
    float alpha = (core + glow * (1 - core)) * in.color.a;
    if (in.style.z > 0) {
        float along = t * sqrt(lengthSquared) + in.style.w;
        float dash = fmod(along, in.style.z);
        float gate = 1 - smoothstep(in.style.z * 0.56 - edge, in.style.z * 0.56 + edge, dash);
        alpha *= gate;
    }
    // Blend along the whole capsule, including its glow. Endpoint RGB uses the
    // reserved detail lanes, keeping the instance stride and buffer size intact.
    float3 color = mix(in.color.rgb, in.detail.yzw, t);
    if (lengthSquared < 0.0001 && in.detail.x == 0) {
        color = mix(color, float3(1), 0.52 * (1 - smoothstep(0.0, radius, distance)));
    }
    return half4(half3(color * alpha), half(alpha));
}

struct InstrumentRaster {
    float4 position [[position]];
    float2 point;
};

vertex InstrumentRaster instrumentVertex(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(1)]]) {
    const float2 coordinates[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    float2 position = coordinates[vertexID];
    InstrumentRaster out;
    out.position = float4(position, 0, 1);
    out.point = float2((position.x + 1) * 0.5, (1 - position.y) * 0.5) * uniforms.viewport.xy;
    return out;
}

fragment half4 instrumentFragment(InstrumentRaster in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]]) {
    float2 size = uniforms.viewport.xy;
    float2 center = (in.point - size * 0.5) / max(size.x, size.y);
    float vignette = clamp(1 - dot(center, center) * 1.7, 0.35, 1.0);
    float3 base = mix(float3(0.022, 0.047, 0.038), float3(0.027, 0.043, 0.066), uniforms.appearance.x);
    float2 cell = abs(fract((in.point - size * 0.5) / 32 + 0.5) - 0.5) * 32;
    float grid = 1 - smoothstep(0.2, 0.75, min(cell.x, cell.y));
    float major = 1 - smoothstep(0.25, 0.7, min(abs(in.point.x - size.x * 0.5), abs(in.point.y - size.y * 0.5)));
    float3 gridColor = mix(float3(0.075, 0.13, 0.092), float3(0.065, 0.115, 0.16), uniforms.appearance.x);
    float scanline = 0.96 + 0.04 * cos(in.point.y * 3.14159265);
    float3 color = (base + gridColor * (grid * 0.22 + major * 0.15)) * vignette * scanline;
    return half4(half3(color), 1);
}
