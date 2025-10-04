#include "Common.metal"

fragment float4 fragment_glitch_wave(VertexOut in [[stage_in]],
                                     texture2d<float> screenTexture [[texture(0)]],
                                     constant float& time [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    
    float waveStrength = 0.015;
    float waveFreq = 8.0;
    float waveSpeed = 2.0;
    
    uv.x += sin(uv.y * waveFreq + time * waveSpeed) * waveStrength;
    uv.y += cos(uv.x * waveFreq * 0.8 + time * waveSpeed * 1.2) * waveStrength * 0.7;
    
    float2 center = float2(0.5, 0.5);
    float2 offset = uv - center;
    float dist = length(offset);
    float radialWave = sin(dist * 15.0 - time * 3.0) * 0.008;
    uv += normalize(offset) * radialWave * dist;
    
    float noise1 = fract(sin(dot(uv + time * 0.1, float2(12.9898, 78.233))) * 43758.5453);
    float noise2 = fract(sin(dot(uv * 3.7 + time * 0.2, float2(39.346, 11.135))) * 31642.7392);
    float noise3 = fract(sin(dot(uv * 7.3 + time * 0.15, float2(73.156, 52.742))) * 26829.1673);
    
    uv = clamp(uv, 0.0, 1.0);
    
    float4 color = screenTexture.sample(textureSampler, uv);
    
    if (noise1 > 0.90 || (noise2 > 0.92 && noise3 > 0.88)) {
        color = mix(color, float4(1.0, 1.0, 1.0, 1.0), 0.8);
    }
    
    float flicker = sin(time * 12.0) * 0.05 + 0.95;
    color.rgb *= flicker;
    
    if (noise2 > 0.98) {
        color.r += 0.3;
    }
    
    return color;
}
