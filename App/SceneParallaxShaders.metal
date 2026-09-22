#include <metal_stdlib>
using namespace metal;

struct ParallaxUniforms {
    float4 region;
    float4 motion; // xy 为归一化位移
    float4 mask;   // 点数组起点、数量、是否反向、是否启用遮罩
};
struct ParallaxOutput { float4 position [[position]]; float2 uv; };

// 距离在原图像素空间计算，不因照片长宽比而改变边缘宽度。
float contourDistance(float2 p, constant float2 *points, uint start, uint count,
                      float2 dimensions, thread float2 &nearest) {
    bool inside = false;
    float best = 1e20;
    float2 previous = points[start + count - 1] * dimensions;
    for (uint i = 0; i < count; ++i) {
        float2 next = points[start + i] * dimensions;
        if ((next.y > p.y) != (previous.y > p.y) &&
            p.x < (previous.x - next.x) * (p.y - next.y) / (previous.y - next.y) + next.x) inside = !inside;
        float2 edge = next - previous;
        float2 q = previous + edge * clamp(dot(p - previous, edge) / max(dot(edge, edge), 1e-6), 0.0, 1.0);
        float distance = length(p - q);
        if (distance < best) { best = distance; nearest = q; }
        previous = next;
    }
    return inside ? best : -best;
}

vertex ParallaxOutput sceneParallaxVertex(uint index [[vertex_id]], constant ParallaxUniforms &u [[buffer(0)]]) {
    constexpr float2 corners[6] = {float2(0,0),float2(1,0),float2(0,1),float2(0,1),float2(1,0),float2(1,1)};
    float2 uv = u.region.xy + corners[index] * u.region.zw;
    float2 p = uv + u.motion.xy;
    return {float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1), uv};
}

fragment float4 sceneParallaxFragment(ParallaxOutput in [[stage_in]],
                                      texture2d<float> photo [[texture(0)]],
                                      constant ParallaxUniforms &u [[buffer(0)]],
                                      constant float2 *points [[buffer(1)]]) {
    constexpr sampler sampling(filter::linear, address::clamp_to_edge);
    float alpha = 1;
    if (u.mask.w > 0) {
        float2 nearest;
        float2 dimensions(photo.get_width(), photo.get_height());
        float distance = contourDistance(in.uv * dimensions, points, uint(u.mask.x), uint(u.mask.y), dimensions, nearest);
        if (u.mask.z > 0) distance = -distance;
        float feather = u.mask.z > 0 ? 2.0 : 10.0;
        alpha = smoothstep(-feather, feather, distance);
    }
    float4 color = photo.sample(sampling, in.uv);
    return float4(color.rgb * alpha, color.a * alpha);
}

// 只在初始化时补齐遮挡轮廓内侧的 48 px 窄带。整图其余像素仍来自原照片。
// 使用轮廓外侧的短程纹理延展，避免跨过桌面/地图等材质边界，也不改变物体形状。
kernel void sceneParallaxRepair(texture2d<float, access::sample> original [[texture(0)]],
                                texture2d<float, access::write> repaired [[texture(1)]],
                                constant float2 *points [[buffer(0)]],
                                constant float4 *masks [[buffer(1)]],
                                constant uint &count [[buffer(2)]],
                                uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= repaired.get_width() || pixel.y >= repaired.get_height()) return;
    constexpr sampler sampling(filter::linear, address::clamp_to_edge);
    float2 dimensions(repaired.get_width(), repaired.get_height());
    float2 p = float2(pixel) + 0.5;
    float2 donor = p;
    for (uint i = 0; i < count; ++i) {
        float4 mask = masks[i];
        float2 nearest;
        float distance = contourDistance(p, points, uint(mask.x), uint(mask.y), dimensions, nearest);
        if (mask.z > 0) distance = -distance;
        if (distance <= 0 || distance > 48) continue;
        float2 direction = normalize(nearest - p);
        donor = nearest + direction * (3.0 + fmod(distance, 3.0));
        // 相邻物件之间不能沿同一方向盲目延伸，否则会取到邻近物件。
        // 从轮廓附近寻找最近的无遮挡纹理，搜索仅发生在初始化的窄带内。
        bool valid = false;
        for (uint attempt = 0; attempt < 193; ++attempt) {
            float2 candidate = donor;
            if (attempt > 0) {
                uint sample = attempt - 1;
                float angle = float(sample % 16) * 0.3926990817;
                float radius = float(sample / 16 + 1) * 8;
                candidate = nearest + float2(cos(angle), sin(angle)) * radius;
            }
            bool occluded = any(candidate < 0) || any(candidate >= dimensions);
            for (uint j = 0; j < count && !occluded; ++j) {
                float2 q;
                float d = contourDistance(candidate, points, uint(masks[j].x), uint(masks[j].y), dimensions, q);
                if (masks[j].z > 0) d = -d;
                occluded = d > -2;
            }
            if (!occluded) { donor = candidate; valid = true; break; }
        }
        if (!valid) donor = p;
        break;
    }
    repaired.write(original.sample(sampling, donor / dimensions), pixel);
}
