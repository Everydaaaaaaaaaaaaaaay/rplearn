import CoreKit
import SwiftUI

/// 咕咕与嘎嘎的稳定语义姿态。资产名只在设计系统中维护，业务页不直接拼接。
public enum BrandMascotPose: CaseIterable, Equatable, Sendable {
    case greeting
    case guide
    case coach
    case celebrate
    case resting
    case reminder
    case encouragement
    case achievement

    var assetName: String {
        switch self {
        case .greeting: "mascot_gugu_welcome"
        case .guide: "mascot_gugu_explore"
        case .coach: "mascot_gaga_think"
        case .celebrate: "mascot_gugu_celebrate"
        case .resting: "mascot_gugu_rest"
        case .reminder: "mascot_gaga_pout"
        case .encouragement: "mascot_gaga_care"
        case .achievement: "mascot_gaga_proud"
        }
    }

    var characterName: String {
        switch self {
        case .greeting, .guide, .celebrate, .resting:
            AppBrand.mascotName
        case .coach, .reminder, .encouragement, .achievement:
            "嘎嘎"
        }
    }

    var actionDescription: String {
        switch self {
        case .greeting: "向你打招呼"
        case .guide: "为你指路"
        case .coach: "正在认真思考"
        case .celebrate: "为你庆祝"
        case .resting: "正在安静休息"
        case .reminder: "轻轻提醒你"
        case .encouragement: "正在鼓励你"
        case .achievement: "认可你的进步"
        }
    }

    var accessibilityLabel: String {
        "\(characterName)\(actionDescription)"
    }
}

/// 品牌吉祥物的统一渲染入口，只使用当前 2D 动作资源包。
public struct BrandMascotView: View {
    private let pose: BrandMascotPose
    private let size: CGFloat
    private let showsShadow: Bool

    public init(
        pose: BrandMascotPose,
        size: CGFloat,
        showsShadow: Bool = true
    ) {
        self.pose = pose
        self.size = size
        self.showsShadow = showsShadow
    }

    public var body: some View {
        Image(pose.assetName)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(
                color: showsShadow ? Color.dsBrandInk.opacity(0.16) : .clear,
                radius: size * 0.07,
                y: size * 0.035
            )
            .accessibilityLabel(pose.accessibilityLabel)
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
