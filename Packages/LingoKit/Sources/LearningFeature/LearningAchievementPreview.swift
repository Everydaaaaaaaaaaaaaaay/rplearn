#if DEBUG
import DesignSystem
import SwiftUI

/// Local presentation-only controls. Never calls a service or writes learning progress.
public struct LearningAchievementPreview: View {
    @State private var startingStars = 3
    @State private var earned = 3
    @State private var award: LearningStarAward?
    @State private var showPromotion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}
    public var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(spacing: 22) {
                Text("动效预览 · 不改变账号进度").font(.footnote).foregroundStyle(.white.opacity(0.65))
                    .accessibilityIdentifier("learning.achievement.preview-notice")
                VStack(spacing: 18) {
                    Spacer(minLength: 180)
                    Text("高中三年级").font(.headline)
                    LearningAchievementStars(earned: earned, award: award) { id in
                        if award?.id == id { award = nil }
                    }
                    .id("achievement.preview.stars")
                }.padding(24).frame(maxWidth: .infinity)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 26))
                    .overlay { RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.08)) }
                Picker("起始星数", selection: $startingStars) {
                    ForEach([0, 3, 8], id: \.self) { count in Text("\(count) 颗星").tag(count) }
                }.pickerStyle(.segmented).disabled(award != nil)
                    .accessibilityIdentifier("learning.achievement.starting-stars")
                if reduceMotion { Text("已启用减少动态效果，预览采用直接点亮和淡入。 ").font(.footnote).foregroundStyle(.secondary) }
            }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    action(award == nil ? "播放升星" : "跳过升星", id: "learning.achievement.play-star") {
                        if award != nil { award = nil } else { play(count: 1) }
                    }
                    action("连续三颗", id: "learning.achievement.play-multiple") { play(count: 3) }.disabled(award != nil)
                }
                action("预览晋升仪式", id: "learning.achievement.play-promotion") { award = nil; showPromotion = true }
            }.padding(20).background(Color(red: 0.035, green: 0.055, blue: 0.13).opacity(0.96))
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .onChange(of: award?.id) { _, id in
            if id != nil { reader.scrollTo("achievement.preview.stars", anchor: .center) }
        }
        .onChange(of: startingStars) { _, value in earned = value; award = nil }
        .fullScreenCover(isPresented: $showPromotion) {
            LearningPromotionCelebration(fromLevel: "senior3", toLevel: "undergraduate", message: "Take your time. We can read it together.", close: { showPromotion = false }, continueJourney: { showPromotion = false })
        }
        .background { LearningAchievementBackdrop() }.foregroundStyle(.white).tint(LearningAchievementGold.light)
        .navigationTitle("升星与晋升预览").navigationBarTitleDisplayMode(.inline).preferredColorScheme(.dark)
        }
    }
    private func play(count: Int) {
        award = .init(level: "senior3", from: startingStars, to: min(9, startingStars + count))
        earned = min(9, startingStars + count)
    }
    private func action(_ title: String, id: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(LearningAchievementGold.main.opacity(0.35)) }
        }.buttonStyle(LearningPressStyle()).accessibilityIdentifier(id)
    }
}
#endif
