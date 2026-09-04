#include <metal_stdlib>
using namespace metal;

struct HomePerspectiveVertexUniforms {
    float4 homographyColumn0;
    float4 homographyColumn1;
    float4 homographyColumn2;
    // xy = 平面中心，zw = 平面宽高
    float4 region;
    // x = 局部缩放，yz = 照片归一化坐标中的屏幕位移
    float4 transform;
};

struct HomePerspectiveFragmentUniforms {
    float4 tint;
    // x = pass（0 实体核心 / 1 预模糊光影层），y = opacity，w = 核心 LOD 偏移
    float4 parameters;
};

struct HomePerspectiveRasterizerData {
    float4 position [[position]];
    float2 textureCoordinate;
};

vertex HomePerspectiveRasterizerData homePerspectiveVertex(
    uint vertexID [[vertex_id]],
    constant HomePerspectiveVertexUniforms &uniforms [[buffer(0)]]
) {
    constexpr float2 corners[6] = {
        float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
        float2(0.0, 1.0), float2(1.0, 0.0), float2(1.0, 1.0)
    };
    float2 textureCoordinate = corners[vertexID];
    float2 centered = (textureCoordinate - 0.5) * uniforms.transform.x;
    float2 planeCoordinate = uniforms.region.xy + centered * uniforms.region.zw;

    float3 h0 = uniforms.homographyColumn0.xyz;
    float3 h1 = uniforms.homographyColumn1.xyz;
    float3 h2 = uniforms.homographyColumn2.xyz;
    float3 projected = h0 * planeCoordinate.x + h1 * planeCoordinate.y + h2;
    projected.xy += uniforms.transform.yz * projected.z;

    HomePerspectiveRasterizerData output;
    // 照片坐标原点在左上；Metal 裁剪坐标原点在中心且 Y 轴向上。
    output.position = float4(
        2.0 * projected.x - projected.z,
        projected.z - 2.0 * projected.y,
        0.0,
        projected.z
    );
    output.textureCoordinate = textureCoordinate;
    return output;
}

fragment float4 homePerspectiveFragment(
    HomePerspectiveRasterizerData input [[stage_in]],
    texture2d<float> texture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant HomePerspectiveFragmentUniforms &uniforms [[buffer(0)]]
) {
    float pass = uniforms.parameters.x;
    float opacity = uniforms.parameters.y;

    if (pass < 0.5) {
        // 轻微偏向更高分辨率 mip，让倾斜地面上的正面笔画保持实体锐度；
        // 各向异性过滤仍负责抑制远端闪烁和锯齿。
        float4 center = texture.sample(
            textureSampler,
            input.textureCoordinate,
            bias(uniforms.parameters.w)
        );
        // UIKit 纹理是预乘 alpha；这里保持预乘混合，避免文字边缘出现暗边。
        return float4(center.rgb, center.a) * opacity;
    }

    float4 center = texture.sample(textureSampler, input.textureCoordinate);
    // 光影纹理由 MPS 使用与 SwiftUI 对应的连续高斯核预先生成；这里每层只采样一次。
    float alpha = center.a * uniforms.tint.a * opacity;
    return float4(uniforms.tint.rgb * alpha, alpha);
}
