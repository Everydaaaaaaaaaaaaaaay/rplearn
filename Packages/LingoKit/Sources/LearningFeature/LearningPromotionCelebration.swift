import DesignSystem
import SwiftUI

struct LearningAchievementBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.13)
            RadialGradient(colors: [Color(red: 0.17, green: 0.20, blue: 0.35), .clear], center: .init(x: 0.5, y: 0.36), startRadius: 0, endRadius: 430)
            GeometryReader { geometry in
                ForEach(0..<28) { index in
                    Circle().fill(LearningAchievementGold.light.opacity(index.isMultiple(of: 3) ? 0.36 : 0.14))
                        .frame(width: index.isMultiple(of: 3) ? 2 : 1, height: index.isMultiple(of: 3) ? 2 : 1)
                        .position(x: geometry.size.width * Double((index * 37 + 13) % 100) / 100,
                                  y: geometry.size.height * Double((index * 29 + 7) % 100) / 100)
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct LearningPromotionCrest: View {
    var reveal: Double = 1
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [LearningAchievementGold.main.opacity(0.15 * reveal), .clear], center: .center, startRadius: 10, endRadius: 135))
            Circle().fill(Color(red: 0.075, green: 0.10, blue: 0.19)).padding(40)
            Circle().trim(from: 0, to: reveal).stroke(LinearGradient(colors: [LearningAchievementGold.light, LearningAchievementGold.edge, LearningAchievementGold.main], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5).padding(40).rotationEffect(.degrees(-90))
            Circle().stroke(LearningAchievementGold.main.opacity(0.28), lineWidth: 0.5).padding(48)
            laurel
            LearningGoldStar(glint: reveal).frame(width: 84, height: 84)
                .shadow(color: LearningAchievementGold.main.opacity(0.5), radius: 15)
                .scaleEffect(0.86 + 0.14 * reveal)
        }.frame(width: 270, height: 270).accessibilityHidden(true)
    }
    private var laurel: some View {
        ZStack {
            ForEach(0..<2) { side in
                ForEach(0..<8) { leaf in
                    let angle = Double(leaf) * 0.16 + 0.17
                    let sign: Double = side == 0 ? -1 : 1
                    Ellipse().fill(LinearGradient(colors: [LearningAchievementGold.light, LearningAchievementGold.edge], startPoint: .top, endPoint: .bottom))
                        .frame(width: 8, height: 20)
                        .rotationEffect(.degrees(sign * (Double(leaf) * 7 + 28)))
                        .offset(x: sign * sin(angle) * 113, y: cos(angle) * 113 - 35)
                }
            }
        }.opacity(reveal)
    }
}

/// Shared by the authoritative promotion completion and the isolated preview.
struct LearningPromotionCelebration: View {
    let fromLevel: String
    let toLevel: String
    let message: String
    var animate = true
    var primaryEnabled = true
    var error: String? = nil
    var retry: () -> Void = {}
    let close: () -> Void
    let continueJourney: () -> Void
    @State private var startedAt = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished || !animate || reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let progress = finished || !animate || reduceMotion ? 1 : min(1, max(0, elapsed / 2.7))
            ScrollView {
                VStack(spacing: 20) {
                    Text("晋升完成").font(.caption.weight(.semibold)).tracking(5)
                        .foregroundStyle(LearningAchievementGold.light).padding(.top, 10)
                    crest(progress: progress)
                    VStack(spacing: 14) {
                        Text(learningLevelName(toLevel)).font(.largeTitle.weight(.semibold))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("learning.promotion.new-level")
                        Text("从\(learningLevelName(fromLevel))，迈向新的一程")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.67))
                            .multilineTextAlignment(.center)
                    }
                    .opacity(progress < 0.56 ? 0 : min(1, (progress - 0.56) / 0.20))
                    .offset(y: reduceMotion ? 0 : 12 * (1 - min(1, progress / 0.82)))
                    Text(message).font(.system(.title3, design: .serif)).italic()
                        .multilineTextAlignment(.center).foregroundStyle(LearningAchievementGold.light)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                        .opacity(progress < 0.72 ? 0 : min(1, (progress - 0.72) / 0.18))
                    if let error {
                        VStack(spacing: 8) {
                            Text(error).font(.footnote).multilineTextAlignment(.center)
                            Button("重试同步", action: retry).frame(minHeight: 44)
                        }.padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }
                }.padding(.horizontal, 28).padding(.bottom, 24)
                    .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    if !finished { Button("跳过动画") { finished = true }.accessibilityIdentifier("learning.promotion.skip") }
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("关闭晋升界面")
                }.font(.subheadline).padding(.horizontal, 20)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: continueJourney) {
                    HStack {
                        if !primaryEnabled { ProgressView().tint(Color.black) }
                        Text(primaryEnabled ? "开始新的旅程" : "正在同步档案…").font(.headline)
                        Image(systemName: "arrow.right")
                    }.frame(maxWidth: .infinity, minHeight: 54).padding(.horizontal, 12)
                        .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.025))
                        .background(LinearGradient(colors: [LearningAchievementGold.light, LearningAchievementGold.main], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(LearningPressStyle()).disabled(!primaryEnabled)
                    .accessibilityIdentifier("learning.promotion.begin-journey")
                    .padding(.horizontal, 24).padding(.bottom, 16).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
        }
        .background { LearningAchievementBackdrop() }.foregroundStyle(.white).tint(LearningAchievementGold.light)
        .preferredColorScheme(.dark).toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.success, trigger: finished) { old, new in animate && new && !old }
        .task {
            startedAt = .now
            if !animate || reduceMotion { finished = true; return }
            do { try await Task.sleep(for: .seconds(2.7)); guard !Task.isCancelled else { return }; finished = true } catch {}
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { finished = true } }
    }
    private func crest(progress: Double) -> some View {
        ZStack {
            LearningPromotionCrest(reveal: min(1, max(0, (progress - 0.27) / 0.4)))
                .opacity(progress < 0.27 ? 0 : 1)
            if progress < 0.65 && !reduceMotion {
                ForEach(0..<9) { index in
                    let angle = Double(index) * 2 * .pi / 9 - .pi / 2
                    let converge = min(1, max(0, (progress - 0.12) / 0.44))
                    let radius = 112 * (1 - converge * converge)
                    LearningGoldStar(glint: progress).frame(width: 20, height: 20)
                        .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                        .opacity(progress > 0.52 ? max(0, 1 - (progress - 0.52) / 0.13) : 1)
                }
            }
        }.frame(height: 270).frame(maxWidth: .infinity)
    }
}
