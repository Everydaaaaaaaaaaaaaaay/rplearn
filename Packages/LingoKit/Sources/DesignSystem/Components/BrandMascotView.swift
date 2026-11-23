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

    /// 每个品牌姿态对应 2D 动作资源包里的一张咕咕或嘎嘎插画。
    var puffBird: PuffMascot.Bird {
        switch self {
        case .greeting, .guide, .celebrate, .resting: .gugu
        case .coach, .reminder, .encouragement, .achievement: .gaga
        }
    }

    var puffPose: PuffMascot.Pose {
        switch self {
        case .greeting: .wave
        case .guide: .point
        case .coach: .thinking
        case .celebrate: .celebrate
        case .resting: .sleepy
        case .reminder: .pout
        case .encouragement: .care
        case .achievement: .proud
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

/// 聊天建议由两位品牌伙伴共同给出。分配规则只依赖消息 ID，重绘或重启后不会换人。
public enum DSCoachPersona: CaseIterable, Equatable, Sendable {
    case gugu
    case gaga

    public var title: String {
        switch self {
        case .gugu: "咕咕建议"
        case .gaga: "嘎嘎建议"
        }
    }

    public var pose: BrandMascotPose {
        switch self {
        case .gugu: .guide
        case .gaga: .coach
        }
    }

    /// UUID 末位在 v4 UUID 中仍为完整随机位，用奇偶分桶可稳定获得近似 50/50 分布。
    public static func assigned(to messageID: UUID) -> Self {
        let lastHex = messageID.uuidString.reversed().first(where: \Character.isHexDigit)
        let value = lastHex.flatMap { Int(String($0), radix: 16) } ?? 0
        return value.isMultiple(of: 2) ? .gugu : .gaga
    }
}

/// 品牌吉祥物的统一渲染入口：改版前 2D 动作资源包里的咕咕与嘎嘎（经由 `PuffMascot`）。
public struct BrandMascotView: View {
    private let pose: BrandMascotPose
    private let size: CGFloat
    private let showsShadow: Bool
    private let reactsToTap: Bool

    public init(
        pose: BrandMascotPose,
        size: CGFloat,
        showsShadow: Bool = true,
        reactsToTap: Bool = false
    ) {
        self.pose = pose
        self.size = size
        self.showsShadow = showsShadow
        self.reactsToTap = reactsToTap
    }

    public var body: some View {
        PuffMascot(pose.puffBird, pose: pose.puffPose, size: size, showsShadow: showsShadow, reactsToTap: reactsToTap)
            .accessibilityElement()
            .accessibilityLabel(pose.accessibilityLabel)
            .accessibilityAddTraits(.isImage)
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
                                weight: .bold
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
