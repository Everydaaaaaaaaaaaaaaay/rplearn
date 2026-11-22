import BackendKit
import DesignSystem
import PersistenceKit
import SwiftUI
import UIKit

/// 学习页的主题色：与这位旅伴头像外圈同一种糖果色（按名字稳定分配），各页面一致。
struct LearningTheme {
    static let rewardTint = PuffCandy.mint.deep
    let candy: PuffCandy
    var tint: Color { candy.deep }

    init(name: String) {
        candy = PuffCandy.stable(for: name)
    }
}
func learningLevelName(_ value: String) -> String { DifficultyLevel(rawValue: value)?.displayName ?? value }

/// 学习页的内容卡片：蓬蓬厚卡片。`opacity` 保留给旧调用，白底不再透出背景。
struct LearningPaper: ViewModifier {
    var opacity: Double = 1
    func body(content: Content) -> some View {
        content.padding(Puff.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .puffCard(radius: Puff.Radius.huge)
    }
}

struct LearningPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : (configuration.isPressed ? Puff.Motion.press : Puff.Motion.release),
                       value: configuration.isPressed)
    }
}

/// 学习流程的主按钮：实心糖果按钮。
struct LearningPrimaryButton: View {
    let title: String
    let candy: PuffCandy
    var busy = false
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(.white) }
                Text(title)
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(PuffCandyButtonStyle(candy))
        .disabled(disabled || busy)
    }
}

struct LearningErrorBanner: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "wifi.exclamationmark")
                .font(.puff(.subheadline, Puff.Weight.label))
                .foregroundStyle(Puff.Palette.ink)
            Button("重新载入", action: retry)
                .font(.puff(.subheadline, Puff.Weight.emphasis))
                .foregroundStyle(PuffCandy.tangerine.deep)
                .padding(.vertical, 8)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(PuffCandy.tangerine.wash, in: RoundedRectangle(cornerRadius: Puff.Radius.large, style: .continuous))
            .accessibilityElement(children: .contain)
    }
}

struct LearningStars: View {
    let earned: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<9) { index in
                Image(systemName: index < earned ? "star.fill" : "star")
                    .font(.system(size: 19, weight: Puff.Weight.icon, design: .rounded))
                    .foregroundStyle(index < earned ? PuffCandy.sunny.base : Puff.Palette.inkFaint.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("已点亮 \(earned) 颗星，共 9 颗")
    }
}

/// Exact boundaries: 70% belongs to green; 50% belongs to yellow.
enum LearningAccuracyBand: Equatable {
    case high, medium, low

    init(correct: Int, total: Int) {
        let ratio = total > 0 ? Double(correct) / Double(total) : 0
        self = ratio >= 0.7 ? .high : ratio >= 0.5 ? .medium : .low
    }

    var tint: Color {
        switch self {
        case .high: PuffCandy.mint.deep
        case .medium: PuffCandy.sunny.deep
        case .low: PuffCandy.bubblegum.deep
        }
    }
}
