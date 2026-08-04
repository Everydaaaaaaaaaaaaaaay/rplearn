import CoreKit
import MascotKit
import SwiftUI

/// 咕咕的稳定姿态集合。资产名只在设计系统中维护，业务页不直接拼接。
public enum BrandMascotPose: Equatable, Sendable {
    case greeting
    case guide
    case coach
    case celebrate

    fileprivate var assetName: String {
        switch self {
        case .greeting: "BrandMascotGreeting"
        case .guide: "BrandMascotGuide"
        case .coach: "BrandMascotCoach"
        case .celebrate: "BrandMascotCelebrate"
        }
    }

    fileprivate var actionDescription: String {
        switch self {
        case .greeting: "向你打招呼"
        case .guide: "为你指路"
        case .coach: "准备给出英语建议"
        case .celebrate: "为你庆祝"
        }
    }

    public var defaultAnimation: MascotAnimationRequest {
        switch self {
        case .greeting, .guide, .coach:
            .semantic(.idle)
        case .celebrate:
            .semantic(.success)
        }
    }
}

/// 页面可覆盖自动选择策略；小图标默认使用静态稿，重点场景使用动画模型。
public enum BrandMascotRenderingMode: Equatable, Sendable {
    case automatic
    case animatedModel
    case staticArtwork

    public func usesAnimatedModel(at size: CGFloat) -> Bool {
        switch self {
        case .automatic:
            size >= 52
        case .animatedModel:
            true
        case .staticArtwork:
            false
        }
    }
}

/// 品牌吉祥物的统一渲染入口。
public struct BrandMascotView: View {
    @State private var animationController: MascotAnimationController

    private let pose: BrandMascotPose
    private let size: CGFloat
    private let showsShadow: Bool
    private let renderingMode: BrandMascotRenderingMode
    private let animation: MascotAnimationRequest
    private let isPaused: Bool

    public init(
        pose: BrandMascotPose,
        size: CGFloat,
        showsShadow: Bool = true,
        renderingMode: BrandMascotRenderingMode = .automatic,
        animation: MascotAnimationRequest? = nil,
        isPaused: Bool = false
    ) {
        self.pose = pose
        self.size = size
        self.showsShadow = showsShadow
        self.renderingMode = renderingMode
        self.animation = animation ?? pose.defaultAnimation
        self.isPaused = isPaused
        _animationController = State(
            initialValue: MascotAnimationController(
                initialAnimation: animation ?? pose.defaultAnimation
            )
        )
    }

    public var body: some View {
        Group {
            if renderingMode.usesAnimatedModel(at: size) {
                MascotView(
                    controller: animationController,
                    animation: animation,
                    isPaused: isPaused
                ) {
                    staticArtwork
                }
            } else {
                staticArtwork
            }
        }
            .frame(width: size, height: size)
            .shadow(
                color: showsShadow ? Color.dsBrandInk.opacity(0.16) : .clear,
                radius: size * 0.07,
                y: size * 0.035
            )
            .accessibilityLabel("\(AppBrand.mascotName)\(pose.actionDescription)")
    }

    private var staticArtwork: some View {
        Image(pose.assetName)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
    }
}

/// 可在首页、设置页和欢迎页复用的中英文品牌组合。
public struct BrandLockup: View {
    private let pose: BrandMascotPose
    private let compact: Bool

    public init(
        pose: BrandMascotPose = .greeting,
        compact: Bool = false
    ) {
        self.pose = pose
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: compact ? DSSpacing.xs : DSSpacing.sm) {
            BrandMascotView(
                pose: pose,
                size: compact ? 42 : 58,
                showsShadow: false
            )

            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(AppBrand.displayName)
                        .font(
                            .system(
                                compact ? .headline : .title2,
                                design: .rounded,
                                weight: .black
                            )
                        )
                        .foregroundStyle(Color.dsBrandInk)
                    Text(AppBrand.englishName)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.dsSkyDeep)
                        .textCase(.uppercase)
                }

                if !compact {
                    Text(AppBrand.tagline)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(AppBrand.displayName)，\(AppBrand.englishName)，\(AppBrand.tagline)"
        )
    }
}
