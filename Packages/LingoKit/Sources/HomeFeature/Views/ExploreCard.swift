import DesignSystem
import SwiftUI
import UIKit

struct ExploreCard: View {
    let title: String
    let subtitle: String
    let artworkName: String
    let fallbackIcon: String
    let tint: Color
    let progress: Double?

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.9)
                if let progress {
                    ProgressView(value: progress)
                        .tint(.white)
                        .frame(width: 126)
                        .background(.black.opacity(0.14), in: Capsule())
                }
            }
            Spacer(minLength: DSSpacing.sm)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.bold))
                .frame(width: 34, height: 34)
                .background(.white, in: Circle())
                .foregroundStyle(tint)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background {
            ZStack {
                artwork
                LinearGradient(
                    stops: [
                        .init(color: tint, location: 0),
                        .init(color: tint, location: 0.42),
                        .init(color: tint.opacity(0.92), location: 0.47),
                        .init(color: tint.opacity(0.28), location: 0.59),
                        .init(color: .clear, location: 0.68),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.bubble, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.bubble, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.2), radius: 8, y: 4)
    }

    @ViewBuilder
    private var artwork: some View {
        if UIImage(named: artworkName) != nil {
            Image(artworkName)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            tint
            Image(systemName: fallbackIcon)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(.white.opacity(0.2))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 72)
                .accessibilityHidden(true)
        }
    }
}
