import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 与城市背景融为一体的首页状态栏：左侧驻地，右侧学习等级与金币。
struct HomeStatusBar: View {
    let region: Region
    let profile: UserProfileDTO?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    cityIdentity
                        .frame(maxWidth: .infinity, alignment: .leading)
                    statusItems
                }
            } else {
                HStack(spacing: DSSpacing.sm) {
                    cityIdentity
                        .layoutPriority(1)
                    Spacer(minLength: DSSpacing.xs)
                    statusItems
                }
            }
        }
        .padding(.vertical, DSSpacing.xxs)
    }

    private var cityIdentity: some View {
        HStack(spacing: 10) {
            Text(flag(region.countryCode))
                .font(.system(size: 25))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.9), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.75), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                    Text("当前城市 · \(region.countryNameZh)")
                }
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(secondaryForeground)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.75)

                Text(region.nameZh)
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(primaryForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .shadow(color: textShadow, radius: 1, y: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前城市，\(region.nameZh)，\(region.countryNameZh)")
    }

    private var statusItems: some View {
        HStack(spacing: 7) {
            HUDStat(
                title: "等级",
                value: profile?.difficultyLevel.hudShortName ?? "—",
                icon: "star.fill",
                tint: Color.dsQuiz,
                usesMonospacedDigits: false,
                foreground: primaryForeground,
                background: statusBackground,
                accessibilityValue: profile?.difficultyLevel.displayName ?? "载入中"
            )
            HUDStat(
                title: "金币",
                value: profile.map { $0.coins.formatted() } ?? "—",
                icon: "dollarsign",
                tint: Color.dsSunset,
                usesMonospacedDigits: true,
                foreground: primaryForeground,
                background: statusBackground,
                accessibilityValue: profile.map { "\($0.coins)" } ?? "载入中"
            )
        }
    }

    private var primaryForeground: Color {
        colorScheme == .dark ? .white : .black.opacity(0.84)
    }

    private var secondaryForeground: Color {
        colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.56)
    }

    private var statusBackground: Color {
        colorScheme == .dark ? .black.opacity(0.44) : .white.opacity(0.88)
    }

    private var textShadow: Color {
        colorScheme == .dark ? .black.opacity(0.42) : .white.opacity(0.5)
    }

    private func flag(_ countryCode: String) -> String {
        countryCode.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}

private struct HUDStat: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    let usesMonospacedDigits: Bool
    let foreground: Color
    let background: Color
    let accessibilityValue: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint.gradient, in: Circle())

            VStack(alignment: .leading, spacing: -1) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground.opacity(0.58))
                Text(value)
                    .font(
                        .system(
                            .caption,
                            design: usesMonospacedDigits ? .monospaced : .rounded,
                            weight: .heavy
                        )
                    )
                    .foregroundStyle(foreground)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 9)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.68), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }
}

private extension DifficultyLevel {
    var hudShortName: String {
        switch self {
        case .primary1: "小一"
        case .primary2: "小二"
        case .primary3: "小三"
        case .primary4: "小四"
        case .primary5: "小五"
        case .primary6: "小六"
        case .junior1: "初一"
        case .junior2: "初二"
        case .junior3: "初三"
        case .senior1: "高一"
        case .senior2: "高二"
        case .senior3: "高三"
        case .undergraduate: "本科"
        case .postgraduate: "研究生"
        case .advanced: "进阶"
        }
    }
}
