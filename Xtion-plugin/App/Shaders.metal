//
//  Shaders.metal
//  Xtion-plugin
//
//  Created by GH on 9/29/25.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                            constant float *vertices [[buffer(0)]]) {
    VertexOut out;
    
    // 每个顶点有4个float值：x, y, u, v
    uint baseIndex = vertexID * 4;
    float2 position = float2(vertices[baseIndex], vertices[baseIndex + 1]);
    float2 texCoord = float2(vertices[baseIndex + 2], vertices[baseIndex + 3]);
    
    out.position = float4(position, 0.0, 1.0);
    out.texCoord = texCoord;
    
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> screenTexture [[texture(0)]],
                              constant float& time [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    
    // 使用 fmod 限制时间范围，避免效果过度累积
    float limitedTime = fmod(time, 10.0);
    
    // 适中的扭曲强度
    float waveStrength = 0.012;
    float waveFreq = 8.0;
    float waveSpeed = 2.0;
    
    // 多层波浪扭曲
    uv.x += sin(uv.y * waveFreq + limitedTime * waveSpeed) * waveStrength;
    uv.y += cos(uv.x * waveFreq * 0.7 + limitedTime * waveSpeed * 1.3) * waveStrength * 0.8;
    
    // 径向扭曲
    float2 center = float2(0.5, 0.5);
    float2 offset = uv - center;
    float dist = length(offset);
    float radialWave = sin(dist * 15.0 - limitedTime * 2.5) * 0.006;
    uv += normalize(offset) * radialWave * dist;
    
    // 白色花屏点
    float noise1 = fract(sin(dot(uv + limitedTime * 0.1, float2(12.9898, 78.233))) * 43758.5453);
    float noise2 = fract(sin(dot(uv * 3.2 + limitedTime * 0.2, float2(39.346, 11.135))) * 31642.7392);
    
    // 确保UV在有效范围内
    uv = clamp(uv, 0.0, 1.0);
    
    // 采样纹理
    float4 color = screenTexture.sample(textureSampler, uv);
    
    // 适中的白色花屏点
    if (noise1 > 0.92 && noise2 > 0.95) {
        color = mix(color, float4(1.0, 1.0, 1.0, 0.9), 0.7);
    }
    
    // 闪烁效果
    float flicker = sin(limitedTime * 12.0) * 0.08 + 0.92;
    color.rgb *= flicker;
    
    return color;
}
