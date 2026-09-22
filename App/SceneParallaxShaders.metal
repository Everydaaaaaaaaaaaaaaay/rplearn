#include <metal_stdlib>
using namespace metal;

struct ParallaxUniforms {
    float4 region;
    float4 motion; // xy 为归一化位移
    float4 mask;   // 轮廓数组起点、数量、是否反向、是否启用遮罩
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

// 同层可包含多个独立开口，例如拱形上窗的各块玻璃；窗棂仍留在室内层。
float layerDistance(float2 p, constant float2 *points, constant uint2 *ranges,
                    float4 mask, float2 dimensions, thread float2 &nearest) {
    float distance = -1e20;
    for (uint i = 0; i < uint(mask.y); ++i) {
        uint2 range = ranges[uint(mask.x) + i];
        float2 q;
        float d = contourDistance(p, points, range.x, range.y, dimensions, q);
        if (d > distance) { distance = d; nearest = q; }
    }
    return mask.z > 0 ? -distance : distance;
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
                                      constant float2 *points [[buffer(1)]],
                                      constant uint2 *ranges [[buffer(2)]]) {
    constexpr sampler sampling(filter::linear, address::clamp_to_edge);
    float alpha = 1;
    if (u.mask.w > 0) {
        float2 nearest;
        float2 dimensions(photo.get_width(), photo.get_height());
        float distance = layerDistance(in.uv * dimensions, points, ranges, u.mask, dimensions, nearest);
        // 物件轮廓已包含阴影保护带，只保留像素级抗锯齿，减少重复叠影。
        float feather = 2.0;
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
                                constant uint2 *ranges [[buffer(3)]],
                                constant float4 *repairRegions [[buffer(4)]],
                                uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= repaired.get_width() || pixel.y >= repaired.get_height()) return;
    constexpr sampler sampling(filter::linear, address::clamp_to_edge);
    float2 dimensions(repaired.get_width(), repaired.get_height());
    float2 p = float2(pixel) + 0.5;
    float2 donor = p;
    float4 neighborhood = float4(0);
    float neighborhoodWeight = 0;
    for (uint i = 0; i < count; ++i) {
        float4 mask = masks[i];
        float2 nearest;
        float distance = layerDistance(p, points, ranges, mask, dimensions, nearest);
        if (distance <= 0 || distance > 48) continue;
        float2 direction = normalize(nearest - p);
        // 物件使用边界外等宽纹理带，保留二维纹理，不把单行像素拉成条纹。
        // 门洞沿用现有窄带取样；物件额外受桌面/地图材质范围约束。
        if (mask.z > 0) {
            donor = nearest + direction * (3 + fmod(distance, 3.0));
        } else {
            // 沿图像轴延展，避免绕斜边镜像把横向木纹折成鱼骨纹。
            bool horizontal = abs(direction.x) >= abs(direction.y);
            float component = horizontal ? direction.x : direction.y;
            float2 axis = horizontal ? float2(sign(component), 0) : float2(0, sign(component));
            donor = p + axis * (2 * distance / max(abs(component), 0.001) + 2);
        }
        float4 region = repairRegions[i] * dimensions.xyxy;
        float2 searchOrigin = mask.z > 0 ? nearest : donor;
        // 相邻物件之间不能沿同一方向盲目延伸，否则会取到邻近物件。
        // 从轮廓附近寻找最近的无遮挡纹理，搜索仅发生在初始化的窄带内。
        bool valid = false;
        for (uint attempt = 0; attempt < 193; ++attempt) {
            float2 candidate = donor;
            if (attempt > 0) {
                uint sample = attempt - 1;
                float angle = float(sample % 16) * 0.3926990817;
                float radius = float(sample / 16 + 1) * 8;
                candidate = searchOrigin + float2(cos(angle), sin(angle)) * radius;
            }
            bool occluded = any(candidate < 0) || any(candidate >= dimensions);
            if (mask.z <= 0) occluded = occluded || any(candidate < region.xy + 1) || any(candidate >= region.zw - 1);
            for (uint j = 0; j < count && !occluded; ++j) {
                float2 q;
                float d = layerDistance(candidate, points, ranges, masks[j], dimensions, q);
                occluded = d > -2;
            }
            if (!occluded) {
                valid = true;
                if (mask.z > 0 || attempt == 0) { donor = candidate; break; }
                // 受相邻物件或纸边阻挡时，综合同一搜索环上的合法纹理，
                // 避免第一个命中点在相邻像素间突然跳换，形成亮点和碎块。
                float weight = 1.0 / max(dot(candidate - searchOrigin, candidate - searchOrigin), 1.0);
                neighborhood += original.sample(sampling, candidate / dimensions) * weight;
                neighborhoodWeight += weight;
            }
            if (attempt > 0 && attempt % 16 == 0 && neighborhoodWeight > 0) break;
        }
        if (!valid) donor = p;
        break;
    }
    float4 color = neighborhoodWeight > 0 ? neighborhood / neighborhoodWeight : original.sample(sampling, donor / dimensions);
    repaired.write(color, pixel);
}
