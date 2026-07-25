import DesignSystem
import DomainKit
import SwiftUI

struct CityPinView: View {
    enum PinState {
        case current
        case unlocked
        case locked

        var accessibilityText: String {
            switch self {
            case .current: "当前城市"
            case .unlocked: "已解锁"
            case .locked: "未解锁"
            }
        }
    }

    let region: Region
    let state: PinState
    let isSelected: Bool

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if state == .current {
                    Circle()
                        .stroke(Color.dsSky.opacity(0.5), lineWidth: 5)
                        .frame(width: 58, height: 58)
                        .scaleEffect(pulse ? 1.25 : 0.85)
                        .opacity(pulse ? 0 : 0.9)
                }
                Image(systemName: state == .locked ? "mappin.slash.circle.fill" : "mappin.circle.fill")
                    .font(.system(size: state == .current ? 48 : 38))
                    .foregroundStyle(pinColor)
                    .background {
                        if state == .current {
                            Text(flag(region.countryCode))
                                .font(.system(size: 17))
                                .offset(y: -4)
                        }
                    }
                    .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
            }
            Text(region.nameZh)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .dsMaterial(.regularMaterial, in: Capsule())
        }
        .scaleEffect(isSelected ? 1.08 : 1)
        .task {
            guard state == .current, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }

    private var pinColor: Color {
        switch state {
        case .current: .dsSky
        case .unlocked: .dsCyan
        case .locked: .gray
        }
    }

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}
