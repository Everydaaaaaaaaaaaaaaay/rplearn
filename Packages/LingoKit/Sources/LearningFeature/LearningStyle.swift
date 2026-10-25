import BackendKit
import DesignSystem
import PersistenceKit
import SwiftUI
import UIKit

struct LearningTheme {
    static let rewardTint = Color(light: UIColor(red: 0.16, green: 0.43, blue: 0.29, alpha: 1),
                                  dark: UIColor(red: 0.54, green: 0.82, blue: 0.65, alpha: 1))
    let tint: Color
    let symbol: String
    let caption: String
    init(role: String) {
        switch role {
        case "ruby":
            tint = Color(light: UIColor(red: 0.1, green: 0.44, blue: 0.43, alpha: 1),
                         dark: UIColor(red: 0.42, green: 0.82, blue: 0.77, alpha: 1))
            symbol = "water.waves"; caption = "海岸边的活动册"
        case "marcus":
            tint = Color(light: UIColor(red: 0.59, green: 0.34, blue: 0.12, alpha: 1),
                         dark: UIColor(red: 0.93, green: 0.69, blue: 0.41, alpha: 1))
            symbol = "camera.aperture"; caption = "街头的语言手记"
        default:
            tint = Color(light: UIColor(red: 0.32, green: 0.30, blue: 0.55, alpha: 1),
                         dark: UIColor(red: 0.73, green: 0.70, blue: 0.96, alpha: 1))
            symbol = "bookmark.fill"; caption = "旅伴的学习手册"
        }
    }
}
func learningLevelName(_ value: String) -> String { DifficultyLevel(rawValue: value)?.displayName ?? value }

struct LearningPaper: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.06)) }
    }
}
struct LearningPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
struct LearningPrimaryButton: View {
    let title: String
    let tint: Color
    var busy = false
    var disabled = false
    let action: () -> Void
    private let labelColor = Color(light: .white, dark: UIColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1))
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(labelColor) }
                Text(title).font(.headline)
            }.frame(maxWidth: .infinity).padding(.vertical, 17)
                .foregroundStyle(labelColor)
                .background(tint.opacity(disabled ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(LearningPressStyle()).disabled(disabled || busy)
    }
}
struct LearningErrorBanner: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "wifi.exclamationmark").font(.subheadline)
            Button("重新载入", action: retry).font(.subheadline.bold()).padding(.vertical, 8)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
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
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(index < earned ? tint : Color.secondary.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("已点亮 \(earned) 颗星，共 9 颗")
    }
}
