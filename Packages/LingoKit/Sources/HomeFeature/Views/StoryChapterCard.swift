import DesignSystem
import SwiftUI

/// 主线与城市剧情共用的章节卡，统一美术、信息层级和状态表达。
struct StoryChapterCard: View {
    let artworkName: String
    let countryCode: String?
    let artworkBadge: String?
    let eyebrow: String
    let badge: String?
    let title: String
    let subtitle: String
    let statusText: String
    let statusIcon: String
    let accent: Color
    let isHighlighted: Bool
    let isDimmed: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            artwork

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(eyebrow)
                        .font(.caption.weight(.black))
                        .foregroundStyle(accent)
                        .lineLimit(1)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .foregroundStyle(.white)
                            .background(accent, in: Capsule())
                            .fixedSize()
                    }
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(accent)
                    } else {
                        Image(systemName: statusIcon)
                    }
                    Text(statusText)
                }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isDimmed ? Color.secondary : accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(DSSpacing.sm)
        .background(Color.dsSurface)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(isHighlighted ? accent.opacity(0.45) : Color.dsBorder, lineWidth: 1)
        }
        .opacity(isDimmed ? 0.58 : 1)
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            Image(artworkName)
                .resizable()
                .scaledToFill()
                .frame(width: 92, height: 108)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.58)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(countryCode.map(flag) ?? "🌍")
                .font(.title3)
                .padding(8)

            if let artworkBadge {
                Text(artworkBadge)
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 92, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous))
        .accessibilityHidden(true)
    }

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}
