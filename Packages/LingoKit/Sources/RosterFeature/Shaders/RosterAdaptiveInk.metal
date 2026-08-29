#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// Maps every scene pixel covered by a glyph to a high-contrast ink branch. The
/// derivative-aware transition stays local to photographic edges instead of flipping
/// an entire label when its average luminance crosses a threshold.
[[ stitchable ]] half4 rosterAdaptiveInk(
    float2 position,
    half4 scene,
    float frameMinY,
    float screenHeight
) {
    half luminance = dot(scene.rgb, half3(0.2126h, 0.7152h, 0.0722h));
    const half normalizedY = half(clamp(
        (frameMinY + position.y) / max(screenHeight, 1.0f),
        0.0f,
        1.0f
    ));

    // Match DSSceneBackdrop's warm atmospheric wash.
    if (normalizedY <= 0.42h) {
        const half wash = mix(0.17h, 0.06h, normalizedY / 0.42h);
        luminance = mix(luminance, 1.0h, wash);
    } else {
        const half wash = 0.12h * ((normalizedY - 0.42h) / 0.58h);
        luminance *= 1.0h - wash;
    }

    // Match the contact scene and the restrained dark readability veil below the glass.
    half sceneDarkening;
    if (normalizedY < 0.24h) {
        sceneDarkening = 0.06h * (normalizedY / 0.24h);
    } else if (normalizedY < 0.58h) {
        sceneDarkening = mix(0.06h, 0.16h, (normalizedY - 0.24h) / 0.34h);
    } else {
        sceneDarkening = mix(0.16h, 0.24h, (normalizedY - 0.58h) / 0.42h);
    }
    luminance *= (1.0h - sceneDarkening) * 0.89h;

    const half transitionWidth = max(fwidth(luminance) * 1.35h, 0.014h);
    const half darkInkAmount = smoothstep(
        0.41h - transitionWidth,
        0.41h + transitionWidth,
        luminance
    );
    const half3 lightInk = half3(0.985h, 0.992h, 1.0h);
    const half3 darkInk = half3(0.025h, 0.055h, 0.085h);

    return half4(mix(lightInk, darkInk, darkInkAmount), scene.a);
}
