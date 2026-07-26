import DesignSystem
import DomainKit
import SwiftUI

/// 与地图融为一体的轻量游戏 HUD：当前驻地 + 可用旅行资源。
struct MapStatusHUD: View {
    let currentRegion: Region?
    let ticketCount: Int
    let coins: Int?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            locationIdentity
                .layoutPriority(1)
            Spacer(minLength: DSSpacing.xs)
            resources
        }
        .padding(.vertical, DSSpacing.xxs)
    }

    private var locationIdentity: some View {
        HStack(spacing: 10) {
            Text(currentRegion?.flagEmoji ?? "🌍")
                .font(.system(size: 24))
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.92), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.76), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                    Text("世界地图 · 当前驻地")
                }
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(secondaryForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

                Text(currentRegion?.nameZh ?? "正在载入")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(primaryForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .shadow(color: textShadow, radius: 1, y: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            currentRegion.map { "当前驻地，\($0.nameZh)，\($0.countryNameZh)" }
                ?? "正在载入当前驻地"
        )
    }

    private var resources: some View {
        HStack(spacing: 7) {
            DSHUDStat(
                title: "机票",
                value: ticketCount.formatted(),
                icon: "ticket.fill",
                tint: .dsSky,
                foreground: primaryForeground,
                background: resourceBackground
            )
            DSHUDStat(
                title: "金币",
                value: coins?.formatted() ?? "—",
                icon: "dollarsign",
                tint: .dsSunset,
                foreground: primaryForeground,
                background: resourceBackground
            )
        }
    }

    private var primaryForeground: Color {
        colorScheme == .dark ? .white : .black.opacity(0.84)
    }

    private var secondaryForeground: Color {
        colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.56)
    }

    private var resourceBackground: Color {
        colorScheme == .dark ? .black.opacity(0.44) : .white.opacity(0.88)
    }

    private var textShadow: Color {
        colorScheme == .dark ? .black.opacity(0.42) : .white.opacity(0.5)
    }
}
