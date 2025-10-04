#include "Common.metal"

fragment float4 fragment_block_glitch(VertexOut in [[stage_in]],
                                      texture2d<float> screenTexture [[texture(0)]],
                                      constant float& time [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    
    float blockHeight = 0.05;
    float blockY = floor(uv.y / blockHeight);
    
    float blockSeed = blockY * 7.123 + time * 0.3;
    float blockRandom = fract(sin(blockSeed) * 43758.5453);
    
    float glitchThreshold = 0.85;
    bool isGlitched = blockRandom > glitchThreshold;
    
    float blockOffset = 0.0;
    if (isGlitched) {
        float offsetRandom = fract(sin(blockSeed * 2.345) * 12345.6789);
        blockOffset = (offsetRandom - 0.5) * 0.1;
    }
    
    float2 glitchedUV = uv;
    glitchedUV.x += blockOffset;
    
    float4 color;
    
    if (isGlitched) {
        float chromaticOffset = 0.008;
        
        float channelSeed = blockSeed * 3.456;
        float channelRandom1 = fract(sin(channelSeed) * 11111.1111);
        float channelRandom2 = fract(sin(channelSeed * 2.0) * 22222.2222);
        float channelRandom3 = fract(sin(channelSeed * 3.0) * 33333.3333);
        
        bool disperseR = channelRandom1 > 0.5;
        bool disperseG = channelRandom2 > 0.5;
        bool disperseB = channelRandom3 > 0.5;
        
        float directionRandom = fract(sin(channelSeed * 4.0) * 44444.4444);
        float direction = directionRandom > 0.5 ? 1.0 : -1.0;
        
        float2 offsetR = disperseR ? float2(chromaticOffset * direction, 0.0) : float2(0.0);
        float2 offsetG = disperseG ? float2(chromaticOffset * direction * 0.5, 0.0) : float2(0.0);
        float2 offsetB = disperseB ? float2(chromaticOffset * -direction, 0.0) : float2(0.0);
        
        float r = screenTexture.sample(textureSampler, clamp(glitchedUV + offsetR, 0.0, 1.0)).r;
        float g = screenTexture.sample(textureSampler, clamp(glitchedUV + offsetG, 0.0, 1.0)).g;
        float b = screenTexture.sample(textureSampler, clamp(glitchedUV + offsetB, 0.0, 1.0)).b;
        
        color = float4(r, g, b, 1.0);
        
        float noiseLine = fract(sin(blockY * 1234.5678 + time * 0.5) * 9876.5432);
        if (noiseLine > 0.97) {
            color.rgb = mix(color.rgb, float3(1.0), 0.3);
        }
        
        if (blockRandom > 0.95) {
            color.r *= 1.1;
            color.b *= 0.9;
        }
    } else {
        color = screenTexture.sample(textureSampler, glitchedUV);
    }
    
    return color;
}
