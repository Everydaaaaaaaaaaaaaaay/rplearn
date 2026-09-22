#include <metal_stdlib>
using namespace metal;

struct DeskSpatialOutput {
    float4 position [[position]];
    float2 uv;
};

vertex DeskSpatialOutput deskSpatialVertex(
    uint index [[vertex_id]],
    constant float4 *vertices [[buffer(0)]],
    constant float4 &camera [[buffer(1)]]
) {
    // 网格的 xy 是原图坐标，z 是与 SwiftUI 入口共享的深度系数。
    float4 sample = vertices[index];
    float2 point = sample.xy + camera.xy * sample.z;
    DeskSpatialOutput output;
    output.position = float4(point.x * 2 - 1, 1 - point.y * 2, 0, 1);
    output.uv = sample.xy;
    return output;
}

fragment float4 deskSpatialFragment(
    DeskSpatialOutput input [[stage_in]],
    texture2d<float> photo [[texture(0)]]
) {
    constexpr sampler sampling(filter::linear, address::clamp_to_edge);
    return photo.sample(sampling, input.uv);
}
