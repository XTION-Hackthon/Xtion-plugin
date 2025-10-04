//
//  GlitchWave.metal
//  Xtion-plugin
//
//  故障波浪特效 - 结合波浪扭曲、白色花屏和屏幕闪烁的诡异效果
//

#include "Common.metal"

fragment float4 fragment_glitch_wave(VertexOut in [[stage_in]],
                                     texture2d<float> screenTexture [[texture(0)]],
                                     constant float& time [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    
    // 增强扭曲效果
    float waveStrength = 0.015; // 适中的扭曲强度
    float waveFreq = 8.0;
    float waveSpeed = 2.0;
    
    // 多层波浪扭曲
    uv.x += sin(uv.y * waveFreq + time * waveSpeed) * waveStrength;
    uv.y += cos(uv.x * waveFreq * 0.8 + time * waveSpeed * 1.2) * waveStrength * 0.7;
    
    // 径向扭曲
    float2 center = float2(0.5, 0.5);
    float2 offset = uv - center;
    float dist = length(offset);
    float radialWave = sin(dist * 15.0 - time * 3.0) * 0.008;
    uv += normalize(offset) * radialWave * dist;
    
    // 多种噪声源产生白色花屏
    float noise1 = fract(sin(dot(uv + time * 0.1, float2(12.9898, 78.233))) * 43758.5453);
    float noise2 = fract(sin(dot(uv * 3.7 + time * 0.2, float2(39.346, 11.135))) * 31642.7392);
    float noise3 = fract(sin(dot(uv * 7.3 + time * 0.15, float2(73.156, 52.742))) * 26829.1673);
    
    // 确保UV在有效范围内
    uv = clamp(uv, 0.0, 1.0);
    
    // 采样纹理
    float4 color = screenTexture.sample(textureSampler, uv);
    
    // 白色花屏效果 - 适中的数量
    if (noise1 > 0.90 || (noise2 > 0.92 && noise3 > 0.88)) {
        color = mix(color, float4(1.0, 1.0, 1.0, 1.0), 0.8);
    }
    
    // 屏幕闪烁效果
    float flicker = sin(time * 12.0) * 0.05 + 0.95;
    color.rgb *= flicker;
    
    // 随机颜色故障
    if (noise2 > 0.98) {
        color.r += 0.3;
    }
    
    return color;
}
