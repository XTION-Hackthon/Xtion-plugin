#include "Common.metal"

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                            constant float *vertices [[buffer(0)]]) {
    VertexOut out;
    
    uint baseIndex = vertexID * 4;
    float2 position = float2(vertices[baseIndex], vertices[baseIndex + 1]);
    float2 texCoord = float2(vertices[baseIndex + 2], vertices[baseIndex + 3]);
    
    out.position = float4(position, 0.0, 1.0);
    out.texCoord = texCoord;
    
    return out;
}
