import BackendKit
import Foundation
import PersistenceKit
import SwiftUI

/// A display receipt, created only after a locally rewarded challenge returns to the page.
struct LearningStarAward: Identifiable, Equatable, Sendable {
    let id: UUID
    let level: String
    let from: Int
    let to: Int
    init?(before: LearningJourney?, after: LearningJourney?, rewardedLevel: String, didEarnPoints: Bool) {
        guard didEarnPoints, let before, let after,
              before.currentLevel == rewardedLevel,
              let old = before.current, let new = after.levels.first(where: { $0.level == rewardedLevel }) else { return nil }
        let from = min(9, max(0, old.stars)), to = min(9, max(0, new.stars))
        guard to > from else { return nil }
        self.init(level: rewardedLevel, from: from, to: to)
    }
    init(level: String, from: Int, to: Int) {
        id = UUID(); self.level = level
        let boundedFrom = min(9, max(0, from))
        self.from = boundedFrom; self.to = min(9, max(boundedFrom, to))
    }
    var count: Int { to - from }
    var duration: Double { 1.4 + Double(max(0, count - 1)) * 0.36 }
    func start(_ offset: Int) -> Double { offset == 0 ? 0 : 1.4 + Double(offset - 1) * 0.36 }
    func flightDuration(_ offset: Int) -> Double { offset == 0 ? 1.4 : 0.36 }
    func landed(at time: Double) -> Int {
        (0..<count).filter { time >= start($0) + flightDuration($0) * 0.84 }.count
    }
}

/// Acknowledges an already-saved level change; presenting it never advances a profile.
struct LearningAutomaticPromotion: Identifiable, Equatable, Sendable {
    let id = UUID()
    let fromLevel: String
    let toLevel: String
    init?(before: LearningJourney?, after: LearningJourney, rewardedLevel: String, didEarnPoints: Bool) {
        guard didEarnPoints, let before, before.currentLevel == rewardedLevel,
              let from = DifficultyLevel(rawValue: rewardedLevel),
              let to = DifficultyLevel(rawValue: after.currentLevel), to.placementOrdinal > from.placementOrdinal,
              let completed = after.levels.first(where: { $0.level == rewardedLevel }), completed.stars >= 9 else { return nil }
        fromLevel = rewardedLevel; toLevel = after.currentLevel
    }
}

enum LearningAchievementGold {
    static let light = Color(red: 1, green: 0.94, blue: 0.68)
    static let main = Color(red: 0.98, green: 0.73, blue: 0.27)
    static let edge = Color(red: 0.65, green: 0.36, blue: 0.08)
}

struct LearningStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) * 0.49
        let points = (0..<10).map { index -> CGPoint in
            let angle = Double(index) * .pi / 5 - .pi / 2
            let r = radius * (index.isMultiple(of: 2) ? 1 : 0.46)
            return CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
        }
        return Path { p in p.addLines(points); p.closeSubpath() }
    }
}

/// One vector master for the flying star, settled stars and the promotion crest.
struct LearningGoldStar: View {
    var glint: Double = 0.4
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                LearningStarShape().fill(LearningAchievementGold.edge).offset(y: size * 0.045)
                LearningStarShape().fill(LinearGradient(colors: [LearningAchievementGold.light, LearningAchievementGold.main, LearningAchievementGold.edge], startPoint: .topLeading, endPoint: .bottomTrailing))
                facets(size: size)
                    .clipShape(LearningStarShape())
                LearningStarShape().stroke(LearningAchievementGold.light.opacity(0.85), lineWidth: max(0.5, size * 0.012))
            }
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
    private func facets(size: CGFloat) -> some View {
        ZStack {
            ForEach(0..<5) { index in
                Path { p in
                    let center = CGPoint(x: size / 2, y: size / 2)
                    let a = Double(index * 2) * .pi / 5 - .pi / 2
                    let b = a + .pi / 5
                    p.move(to: center)
                    p.addLine(to: CGPoint(x: center.x + cos(a) * size * 0.49, y: center.y + sin(a) * size * 0.49))
                    p.addLine(to: CGPoint(x: center.x + cos(b) * size * 0.2254, y: center.y + sin(b) * size * 0.2254))
                    p.closeSubpath()
                }.fill(index < 2 ? Color.white.opacity(0.30) : Color.black.opacity(0.12))
            }
            Rectangle().fill(LinearGradient(colors: [.clear, .white.opacity(0.70), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.16).rotationEffect(.degrees(22))
                .offset(x: size * (glint - 0.5) * 1.7)
        }
    }
}

private struct LearningStarAnchors: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct LearningAchievementStars: View {
    let earned: Int
    var award: LearningStarAward? = nil
    var onCompletion: (UUID) -> Void = { _ in }
    @State private var startedAt = Date()
    @State private var activeID: UUID?
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var playing: Bool { award != nil && !finished && activeID == award?.id }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playing)) { context in
            let time = max(0, context.date.timeIntervalSince(startedAt))
            let settled = displayedStars(at: time)
            HStack(spacing: 6) {
                ForEach(0..<9) { index in
                    ZStack {
                        if index < settled {
                            LearningGoldStar().shadow(color: LearningAchievementGold.main.opacity(0.18), radius: 3)
                        } else {
                            LearningStarShape().stroke(Color.secondary.opacity(0.65), lineWidth: 1.35)
                        }
                    }.frame(width: 18, height: 18)
                        .anchorPreference(key: LearningStarAnchors.self, value: .bounds) { [index: $0] }
                }
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: settled) { old, new in
                award != nil && playing && new > old
            }
            .overlayPreferenceValue(LearningStarAnchors.self) { anchors in
                GeometryReader { proxy in
                    if let award, playing, !reduceMotion {
                        flights(award: award, time: time, anchors: anchors, proxy: proxy)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("已点亮 \(settled) 颗星，共 9 颗")
            .accessibilityValue("\(settled)/9")
            .accessibilityIdentifier("learning.achievement.stars")
        }
        .task(id: award?.id) {
            guard let award else { return }
            activeID = award.id; finished = false; startedAt = .now
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.25 : award.duration))
                guard !Task.isCancelled else { return }
                finish()
            } catch {}
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { finish() } }
        .onChange(of: dynamicTypeSize) { _, _ in finish() }
    }
    private func displayedStars(at time: Double) -> Int {
        guard let award else { return min(9, max(0, earned)) }
        if finished && activeID == award.id { return min(9, max(0, earned)) }
        if reduceMotion { return award.to }
        return award.from + (activeID == award.id ? award.landed(at: time) : 0)
    }
    private func finish() {
        guard let award else { return }
        finished = true; onCompletion(award.id)
    }
    private func flights(award: LearningStarAward, time: Double, anchors: [Int: Anchor<CGRect>], proxy: GeometryProxy) -> some View {
        let available = min(280.0, max(72.0, proxy.frame(in: .global).minY - 130))
        let lift = dynamicTypeSize.isAccessibilitySize ? min(88, available) : available
        return ZStack(alignment: .topLeading) {
            ForEach(0..<award.count, id: \.self) { offset in
                if let anchor = anchors[award.from + offset] {
                    let slot = proxy[anchor]
                    let target = CGPoint(x: slot.midX, y: slot.midY + lift)
                    let local = (time - award.start(offset)) / award.flightDuration(offset)
                    if local >= 0 && local < 1 {
                        LearningStarFlight(progress: local, target: target, width: proxy.size.width, hero: offset == 0)
                    }
                }
            }
        }
        .frame(width: proxy.size.width, height: lift + 50, alignment: .topLeading)
        .offset(y: -lift)
        .onChange(of: proxy.size.width) { _, _ in finish() }
    }
}

struct LearningStarFlight: View {
    let progress: Double
    let target: CGPoint
    let width: CGFloat
    let hero: Bool
    private var p: Double { min(1, max(0, progress)) }
    private var launch: CGPoint { CGPoint(x: width * 0.5, y: hero ? 24 : max(24, target.y - 140)) }
    private var center: CGPoint { CGPoint(x: width * 0.5, y: hero ? min(105, target.y * 0.42) : max(24, target.y - 100)) }
    private var travel: Double { max(0, min(1, (p - (hero ? 0.38 : 0)) / (hero ? 0.46 : 0.84))) }
    private var point: CGPoint {
        if hero && p < 0.38 {
            let t = p / 0.38
            return CGPoint(x: launch.x, y: launch.y + (center.y - launch.y) * (1 - pow(1 - t, 3)))
        }
        let t = travel * travel * (3 - 2 * travel)
        let control = CGPoint(x: min(width - 20, center.x + 70), y: target.y - 125)
        return CGPoint(x: pow(1-t, 2) * center.x + 2*(1-t)*t*control.x + t*t*target.x,
                       y: pow(1-t, 2) * center.y + 2*(1-t)*t*control.y + t*t*target.y)
    }
    private var starSize: CGFloat {
        if !hero { return 32 - travel * 14 }
        let maximum = min(88, max(46, target.y * 0.5))
        if p < 0.38 { return 12 + (maximum - 12) * sin((p / 0.38) * .pi / 2) }
        return maximum - travel * (maximum - 18)
    }
    var body: some View {
        ZStack {
            if p < 0.84 {
                Circle().fill(RadialGradient(colors: [LearningAchievementGold.main.opacity(0.24), .clear], center: .center, startRadius: 0, endRadius: 72))
                    .frame(width: 144, height: 144).position(point)
                if travel > 0 {
                    Path { path in path.move(to: center); path.addQuadCurve(to: point, control: CGPoint(x: min(width - 20, center.x + 70), y: target.y - 125)) }
                        .trim(from: max(0, travel - 0.28), to: 1)
                        .stroke(LinearGradient(colors: [.clear, LearningAchievementGold.light.opacity(0.6)], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: hero ? 2 : 1, lineCap: .round))
                }
                LearningGoldStar(glint: p * 1.5).frame(width: starSize, height: starSize)
                    .rotation3DEffect(.degrees(sin(p * .pi) * 38), axis: (x: 0.3, y: 1, z: 0))
                    .rotationEffect(.degrees(-18 * (1 - travel)))
                    .shadow(color: LearningAchievementGold.main.opacity(0.45), radius: 9)
                    .position(point).opacity(min(1, p * 10))
            } else {
                LearningStarLanding(progress: (p - 0.84) / 0.16).position(target)
            }
        }
    }
}

private struct LearningStarLanding: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(LearningAchievementGold.light.opacity(1-progress), lineWidth: 1)
                .frame(width: 20 + progress * 48, height: 20 + progress * 48)
            ForEach(0..<6) { index in
                let a = Double(index) * .pi / 3
                Circle().fill(LearningAchievementGold.light.opacity(1-progress)).frame(width: 2.5, height: 2.5)
                    .offset(x: cos(a) * (12 + progress * 27), y: sin(a) * (12 + progress * 27))
            }
        }.frame(width: 80, height: 80)
    }
}
