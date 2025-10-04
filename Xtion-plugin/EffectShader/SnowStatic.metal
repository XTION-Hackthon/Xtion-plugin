#include "Common.metal"

fragment float4 fragment_snow_static(VertexOut in [[stage_in]],
                                     texture2d<float> screenTexture [[texture(0)]],
                                     constant float& time [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    float4 color = screenTexture.sample(textureSampler, uv);
    
    float2 center = float2(0.5, 0.5);
    float2 offset = uv - center;
    float distFromCenter = length(offset);
    
    float vignetteRadius = 0.7;
    float vignette = smoothstep(vignetteRadius, 0.2, distFromCenter);
    color.rgb *= mix(0.3, 1.0, vignette);
    
    float centerMask = smoothstep(0.6, 0.2, distFromCenter);
    
    float noise1 = fract(sin(dot(uv * 100.0 + time * 5.0, float2(12.9898, 78.233))) * 43758.5453);
    float noise2 = fract(sin(dot(uv * 50.0 + time * 3.0, float2(39.346, 11.135))) * 31642.7392);
    float noise3 = fract(sin(dot(uv * 200.0 + time * 7.0, float2(73.156, 52.742))) * 26829.1673);
    
    float snowNoise = (noise1 * 0.5 + noise2 * 0.3 + noise3 * 0.2);
    
    float snowIntensity = sin(time * 2.0) * 0.15 + 0.25;
    float snow = snowNoise * snowIntensity * centerMask;
    
    float flicker = sin(time * 17.0) * 0.05 + sin(time * 23.0) * 0.03;
    
    float colorGlitch = fract(sin(time * 0.5) * 100.0);
    if (colorGlitch > 0.95) {
        float channelChoice = fract(sin(time * 1.3) * 50.0);
        if (channelChoice < 0.33) {
            color.r *= 1.3;
        } else if (channelChoice < 0.66) {
            color.g *= 0.7;
        } else {
            color.b *= 1.2;
        }
    }
    
    float ghostFrame = step(0.98, fract(sin(time * 0.7) * 200.0));
    if (ghostFrame > 0.5) {
        float2 distortedUV = uv + float2(sin(uv.y * 20.0 + time * 10.0) * 0.01, 0.0);
        color = screenTexture.sample(textureSampler, distortedUV);
    }
    
    color.rgb = mix(color.rgb, float3(snow), snow);
    
    color.rgb *= (1.0 + flicker);
    
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, float3(gray), 0.3);
    
    return color;
}
