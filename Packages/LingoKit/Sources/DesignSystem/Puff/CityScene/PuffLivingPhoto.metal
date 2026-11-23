#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// 动画以 600 秒为一圈无缝循环：每个频率取整到这 600 秒内的整数圈，
/// App 传入的时间对 600 取模，回绕时画面不跳。
constant float kPuffLoop = 600.0;

static float puffRate(float rate) {
    return round(rate * kPuffLoop / (2.0 * M_PI_F)) * (2.0 * M_PI_F / kPuffLoop);
}

static float puffHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// 风格化地点照片的“活照片”效果。
///
/// - rect：照片在本层里的位置和大小（x, y, 宽, 高），用来把像素对到动态遮罩上。
/// - time：对 600 取模的秒数。
/// - motion：动态遮罩，R=树叶、G=水面、B=远近（1 为最近）。
/// - drift：镜头缓慢漂移的距离，近处挪得多、远处挪得少，形成视差。
/// - sway：树叶摇动、水面波动的幅度（点）。
[[ stitchable ]] half4 puffLivingPhoto(float2 position, SwiftUI::Layer layer, float4 rect, float time,
                                       texture2d<half> motion, float2 drift, float sway) {
    constexpr sampler maskSampler(address::clamp_to_edge, filter::linear);
    float2 uv = (position - rect.xy) / rect.zw;
    half4 mask = motion.sample(maskSampler, uv);
    float leaf = mask.r;
    float water = mask.g;
    float near = mask.b;

    float2 offset = drift * (near - 0.35);
    float gust = 0.55 + 0.45 * sin(time * puffRate(0.6) + uv.x * 2.4 + uv.y * 1.3);
    offset += leaf * sway * gust * float2(sin(time * puffRate(1.7) + position.y * 0.05 + position.x * 0.02) * 1.5,
                                          sin(time * puffRate(1.3) + position.x * 0.04) * 0.6);
    offset += water * sway * float2(sin(position.y * 0.55 + time * puffRate(2.2)) * 1.2,
                                    sin(position.x * 0.09 + time * puffRate(1.4)) * 0.35);
    half4 color = layer.sample(position + offset);

    if (water > 0.3 && color.a > 0.5) {
        // 水面反光处零星的柔和波光：横向拉长的小光斑，各自按相位慢慢亮起再暗下，
        // 只落在明亮、接近无彩色的倒影上（避开水藻和岸边草地），跟着照片一起漂移。
        float3 rgb = float3(color.rgb) / float(color.a);
        float luminance = dot(rgb, float3(0.3, 0.59, 0.11));
        float chroma = max(rgb.r, max(rgb.g, rgb.b)) - min(rgb.r, min(rgb.g, rgb.b));
        float2 cellSize = float2(9.0, 4.0);
        float2 p = position + offset;
        float2 cell = floor(p / cellSize);
        float pick = puffHash(cell);
        if (pick > 0.88) {
            float2 center = (cell + 0.25 + 0.5 * float2(puffHash(cell + 17.0), puffHash(cell + 31.0))) * cellSize;
            float2 d = (p - center) / float2(2.4, 0.7);
            float shape = exp(-dot(d, d));
            float twinkle = pow(max(sin(time * puffRate(0.9 + pick) + pick * 53.0), 0.0), 8.0);
            float glint = smoothstep(0.3, 0.7, water) * smoothstep(0.55, 0.85, luminance)
                * (1.0 - smoothstep(0.12, 0.3, chroma)) * shape * twinkle;
            color.rgb = min(color.rgb + half3(glint * 0.5) * color.a, half3(color.a));
        }
    }
    return color;
}
