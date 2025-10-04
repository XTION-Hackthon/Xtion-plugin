//
//  Vertex.metal
//  Xtion-plugin
//
//  顶点着色器
//

#include "Common.metal"

/// 标准的全屏四边形顶点着色器
/// 输入顶点数据格式: [x, y, u, v] 交错排列
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
