//
//  Common.metal
//  Xtion-plugin
//
//  共享的 Metal 数据结构
//

#ifndef Common_metal
#define Common_metal

#include <metal_stdlib>
using namespace metal;

/// 顶点输出结构
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

#endif /* Common_metal */
