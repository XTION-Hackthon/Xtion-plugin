#include "Common.metal"

fragment float4 fragment_heartbeat_glow(VertexOut in [[stage_in]],
                                        texture2d<float> screenTexture [[texture(0)]],
                                        constant float& time [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    float4 color = screenTexture.sample(textureSampler, uv);
    
    float2 center = float2(0.5, 0.5);
    float2 offset = uv - center;
    float distFromCenter = length(offset);
    
    float distFromEdge = 1.0 - distFromCenter * 1.414;
    
    float heartbeatFreq = 1.0;
    float t = fract(time * heartbeatFreq);
    
    float beat1 = exp(-t * 10.0);
    
    float beat2Phase = t - 0.15;
    float beat2 = 0.0;
    if (beat2Phase > 0.0 && beat2Phase < 0.15) {
        beat2 = exp(-beat2Phase * 10.0) * 0.7;
    }
    
    float heartbeat = max(beat1, beat2);
    
    float edgeFalloff = smoothstep(1.0, 0.5, distFromEdge);
    float glowIntensity = edgeFalloff * heartbeat * 0.5;
    
    float angle = atan2(offset.y, offset.x);
    float radialPulse = sin(angle * 4.0 + time * 2.0) * 0.1 + 0.9;
    glowIntensity *= radialPulse;
    
    float3 glowColor = float3(1.0, 0.1, 0.15);
    float glowAlpha = glowIntensity * 0.5;
    
    color.rgb = mix(color.rgb, glowColor, glowAlpha);
    
    float vignette = smoothstep(0.8, 0.3, distFromCenter);
    color.rgb *= mix(0.85, 1.0, vignette);
    
    return color;
}
