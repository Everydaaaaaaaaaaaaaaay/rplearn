#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// 与 `puffLivingPhoto` 相同：频率取整到 600 秒内的整数圈，时间对 600 取模后无缝循环。
constant float kPuffLoop = 600.0;

static float puffRate(float rate) {
    return round(rate * kPuffLoop / (2.0 * M_PI_F)) * (2.0 * M_PI_F / kPuffLoop);
}

/// 城市全景的水面倒影：按行左右轻晃，`unit` 为一个设计单位对应的点数。
[[ stitchable ]] float2 puffRipple(float2 position, float time, float unit) {
    float row = position.y / max(unit, 0.01);
    float wave = sin(row * 1.7 + time * puffRate(2.0)) + 0.5 * sin(row * 3.1 - time * puffRate(1.3) + position.x / max(unit, 0.01) * 0.05);
    return position + float2(wave * 0.9 * unit, 0);
}

/// 城市地标的受光：贴地处略暗（环境光遮蔽），越高越亮。`horizon` 为岸线在本层的纵坐标（点）。
[[ stitchable ]] half4 puffLandmarkLight(float2 position, half4 color, float horizon, float unit) {
    float height = (horizon - position.y) / max(unit, 0.01);
    float light = mix(0.82, 1.06, smoothstep(0.0, 80.0, height));
    return half4(min(color.rgb * half(light), half3(color.a)), color.a);
}
