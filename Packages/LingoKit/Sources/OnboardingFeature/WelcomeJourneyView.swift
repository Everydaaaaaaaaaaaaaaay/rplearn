import CoreKit
import DesignSystem
import SwiftUI

/// 首次启动的品牌入口：先说明“为什么值得开始”，再进入学习档案。
struct WelcomeJourneyView: View {
    let onBegin: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasAnimated = false
    @State private var showsBrand = false
    @State private var showsHero = false
    @State private var showsCopy = false
    @State private var showsFeatures = false
    @State private var routeProgress: CGFloat = 0
    @State private var visibleStops = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WelcomeBackdrop(colorScheme: colorScheme)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 24 : 20) {
                        brandHeader
                            .dynamicTypeSize(.large)
                            .opacity(showsBrand ? 1 : 0)
                            .offset(y: reduceMotion || showsBrand ? 0 : -10)

                        hero(height: heroHeight(for: geometry.size))
                            .dynamicTypeSize(.large)
                            .opacity(showsHero ? 1 : 0)
                            .scaleEffect(reduceMotion || showsHero ? 1 : 0.965)

                        introduction
                            .opacity(showsCopy ? 1 : 0)
                            .offset(y: reduceMotion || showsCopy ? 0 : 14)

                        featureCard
                            .opacity(showsFeatures ? 1 : 0)
                            .offset(y: reduceMotion || showsFeatures ? 0 : 18)
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionFooter
        }
        .task {
            await playEntranceIfNeeded()
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            BrandLockup(pose: .greeting, compact: true)

            Spacer(minLength: 8)

            Label("为你实时适配", systemImage: "sparkles")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.dsSkyDeep)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color.dsSurface.opacity(0.74), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.dsSky.opacity(0.18), lineWidth: 1)
                }
                .accessibilityLabel("学习内容会根据你的英语水平实时适配")
        }
        .frame(maxWidth: .infinity)
    }

    private func hero(height: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: heroGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18))
                    .frame(width: width * 0.72)
                    .blur(radius: 3)
                    .offset(x: width * 0.34, y: -height * 0.38)

                WelcomeRouteShape()
                    .trim(from: 0, to: routeProgress)
                    .stroke(
                        Color.white.opacity(0.82),
                        style: StrokeStyle(
                            lineWidth: 2.2,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [4, 8]
                        )
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                ForEach(Array(Self.routeStops.enumerated()), id: \.element.name) { index, stop in
                    routeStop(stop, isVisible: visibleStops > index)
                        .position(
                            x: width * stop.position.x,
                            y: height * stop.position.y
                        )
                }

                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        speechBubble
                            .frame(maxWidth: min(width * 0.58, 270), alignment: .leading)
                            .padding(.top, 18)

                        Spacer(minLength: 0)

                        BrandMascotView(
                            pose: .guide,
                            size: min(max(width * 0.43, 142), 214),
                            showsShadow: true
                        )
                        .rotationEffect(.degrees(reduceMotion || showsHero ? 0 : 4))
                        .offset(x: 8, y: -8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)

                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                    Text("你的英语旅程，从一次真实开口开始")
                }
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.black.opacity(0.15), in: Capsule())
                .position(x: width * 0.48, y: height * 0.9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.58), lineWidth: 1)
            }
            .shadow(
                color: Color.dsSkyDeep.opacity(colorScheme == .dark ? 0.2 : 0.16),
                radius: 24,
                y: 12
            )
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("咕咕邀请你从伦敦出发，在不同城市练习真实英语对话")
    }

    private var speechBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fancy exploring together?")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.dsPaperInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("要一起出发吗？")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.dsPaperInkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 12, height: 12)
                .offset(x: 4, y: 4)
        }
        .shadow(color: .black.opacity(0.09), radius: 12, y: 5)
    }

    private var introduction: some View {
        VStack(spacing: 10) {
            Text("让英语，发生在旅途中。")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dsBrandInk)
                .accessibilityAddTraits(.isHeader)

            Text("在城市故事、自然对话与即时点词中，和会记住你的 AI 旅伴一起，把每一次开口变成进步。")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 510)
        }
    }

    private var featureCard: some View {
        VStack(spacing: 0) {
            featureRow(
                icon: "building.2.crop.circle.fill",
                tint: .dsSky,
                title: "走进城市",
                detail: "用剧情和生活场景理解表达"
            )
            featureDivider
            featureRow(
                icon: "person.2.wave.2.fill",
                tint: .dsBrandCoral,
                title: "遇见旅伴",
                detail: "角色会记住对话，关系持续生长"
            )
            featureDivider
            featureRow(
                icon: "text.book.closed.fill",
                tint: .dsQuiz,
                title: "随时点词",
                detail: "翻译、发音和例句在需要时出现"
            )
        }
        .padding(.vertical, 4)
        .dsSceneGlass(
            radius: 22,
            tint: Color.dsSky.opacity(0.035),
            legibility: .enhanced
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("咕游记的三个特点")
    }

    private func featureRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var featureDivider: some View {
        Divider()
            .padding(.leading, 70)
    }

    private var actionFooter: some View {
        VStack(spacing: 8) {
            Button {
                Haptics.impact(.medium)
                onBegin()
            } label: {
                HStack(spacing: 8) {
                    Text("开始我的旅程")
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
            }
            .buttonStyle(.dsActionPrimary)
            .accessibilityIdentifier("welcome.begin")

            Text("先建立学习档案，所有选择之后都能修改")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .dsMaterial(.ultraThinMaterial, in: Rectangle())
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.clear, Color.dsBorder.opacity(0.8), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.7)
        }
        .opacity(showsFeatures ? 1 : 0)
        .offset(y: reduceMotion || showsFeatures ? 0 : 12)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .allowsHitTesting(showsFeatures)
    }

    private func routeStop(_ stop: RouteStop, isVisible: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 9, height: 9)
            }
            Text(stop.name)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .scaleEffect(reduceMotion || isVisible ? 1 : 0.6)
        .opacity(isVisible ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var heroGradient: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.05, green: 0.23, blue: 0.39),
                Color(red: 0.08, green: 0.47, blue: 0.62),
                Color(red: 0.29, green: 0.24, blue: 0.56),
            ]
        }
        return [
            Color(red: 0.20, green: 0.72, blue: 0.94),
            Color(red: 0.18, green: 0.57, blue: 0.88),
            Color(red: 0.47, green: 0.40, blue: 0.91),
        ]
    }

    private func heroHeight(for size: CGSize) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 300 }
        return min(max(size.height * 0.31, 245), 318)
    }

    @MainActor
    private func playEntranceIfNeeded() async {
        guard !hasAnimated else { return }
        hasAnimated = true
        if reduceMotion {
            showsBrand = true
            showsHero = true
            showsCopy = true
            showsFeatures = true
            routeProgress = 1
            visibleStops = Self.routeStops.count
            return
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 1)) {
            showsBrand = true
            showsHero = true
        }
        try? await Task.sleep(for: .milliseconds(130))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.75)) {
            routeProgress = 1
        }
        for index in 1...Self.routeStops.count {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                visibleStops = index
            }
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 1)) {
            showsCopy = true
        }
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 1)) {
            showsFeatures = true
        }
    }

    private struct RouteStop: Sendable {
        let name: String
        let position: UnitPoint
    }

    private static let routeStops = [
        RouteStop(name: "伦敦", position: UnitPoint(x: 0.14, y: 0.72)),
        RouteStop(name: "纽约", position: UnitPoint(x: 0.47, y: 0.5)),
        RouteStop(name: "墨尔本", position: UnitPoint(x: 0.82, y: 0.73)),
    ]
}

private struct WelcomeBackdrop: View {
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            Color.dsBackground

            LinearGradient(
                colors: [
                    Color.dsSky.opacity(colorScheme == .dark ? 0.16 : 0.13),
                    Color.dsBackground.opacity(0.2),
                    Color.dsBrandCoral.opacity(colorScheme == .dark ? 0.06 : 0.045),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.dsCyan.opacity(0.11), .clear],
                center: UnitPoint(x: 0.92, y: 0.14),
                startRadius: 8,
                endRadius: 240
            )

            RadialGradient(
                colors: [Color.dsQuiz.opacity(0.07), .clear],
                center: UnitPoint(x: 0.02, y: 0.72),
                startRadius: 4,
                endRadius: 220
            )
        }
    }
}

private struct WelcomeRouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.1, y: rect.height * 0.73))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.47, y: rect.height * 0.51),
            control1: CGPoint(x: rect.width * 0.22, y: rect.height * 0.56),
            control2: CGPoint(x: rect.width * 0.35, y: rect.height * 0.45)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.86, y: rect.height * 0.73),
            control1: CGPoint(x: rect.width * 0.61, y: rect.height * 0.56),
            control2: CGPoint(x: rect.width * 0.72, y: rect.height * 0.76)
        )
        return path
    }
}
