import CoreKit
import DesignSystem
import DictKit
import PersistenceKit
import SwiftUI
import UIKit

/// 首次启动的品牌入口：用概念展示介绍旅程，再进入学习档案。
public struct WelcomeJourneyView: View {
    let onBegin: () -> Void
    let dictionary: DictDatabase
    let grammar: GrammarPointStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPage: Int? = 0

    private let pageCount = 4

    public init(dictionary: DictDatabase, grammar: GrammarPointStore, onBegin: @escaping () -> Void) {
        self.dictionary = dictionary
        self.grammar = grammar
        self.onBegin = onBegin
    }

    public var body: some View {
        ZStack {
            WelcomeBackdrop(colorScheme: colorScheme)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                topBar

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        page(
                            index: 0,
                            eyebrow: "走进城市生活",
                            title: "在日常的街角，\n遇见新故事。",
                            detail: "去公园走走，在咖啡馆歇脚。一次普通的外出，也能成为故事的开始。",
                            accessibilityID: "welcome.page.city"
                        ) {
                            WelcomeCityScreen(isActive: currentPage == 0, reduceMotion: reduceMotion)
                                .accessibilityIdentifier("welcome.concept.activity")
                        }

                        page(
                            index: 1,
                            eyebrow: "会记住你的 AI 旅伴",
                            title: "对话结束，\n关系不会归零。",
                            detail: "AI 旅伴会记住你聊过的话题和喜好，也有各自的性格与故事。",
                            accessibilityID: "welcome.page.companion"
                        ) {
                            WelcomeConversationScreen(isActive: currentPage == 1, reduceMotion: reduceMotion)
                                .accessibilityIdentifier("welcome.concept.chat")
                        }

                        page(
                            index: 2,
                            eyebrow: "随时点词",
                            title: "不懂就点，\n理解不用离开情境。",
                            detail: "在资料、剧情和聊天里直接查看释义、发音与例句，学完继续聊。",
                            accessibilityID: "welcome.page.dictionary"
                        ) {
                            WelcomeDictionaryScreen(dictionary: dictionary, grammar: grammar)
                                .accessibilityIdentifier("welcome.concept.dictionary")
                        }

                        page(
                            index: 3,
                            eyebrow: "你的第一位旅伴",
                            title: "从一句 Hello，\n认识一个新朋友。",
                            detail: "在开场剧情里认识三位 AI 旅伴，再选择一位，开始你的英语对话。",
                            accessibilityID: "welcome.page.personalized"
                        ) {
                            WelcomePersonalizedScreen(isActive: currentPage == 3, reduceMotion: reduceMotion)
                                .accessibilityIdentifier("welcome.concept.companion")
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedPage)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityLabel("欢迎介绍，共四页")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionFooter
        }
        .sensoryFeedback(.selection, trigger: currentPage)
    }

    private var currentPage: Int {
        min(max(selectedPage ?? 0, 0), pageCount - 1)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            BrandLockup(pose: .greeting, compact: true)

            Spacer(minLength: 8)


        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func page<Demo: View>(
        index: Int,
        eyebrow: String,
        title: String,
        detail: String,
        accessibilityID: String,
        @ViewBuilder demo: @escaping () -> Demo
    ) -> some View {
        let shouldReduceMotion = reduceMotion
        return WelcomePageShell(
            eyebrow: eyebrow,
            title: title,
            detail: detail,
            isActive: currentPage == index,
            demo: demo
        )
        .containerRelativeFrame(.horizontal)
        .id(index)
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.955)
                .rotation3DEffect(
                    .degrees(shouldReduceMotion ? 0 : Double(phase.value) * -3.5),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )
                .opacity(shouldReduceMotion || phase.isIdentity ? 1 : 0.62)
        }
        .accessibilityIdentifier(accessibilityID)
    }

    private var actionFooter: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { page in
                    Button {
                        move(to: page)
                    } label: {
                        Capsule()
                            .fill(page == currentPage ? Color.dsSky : Color.dsBorder)
                            .frame(width: page == currentPage ? 25 : 7, height: 7)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("welcome.pageIndicator.\(page)")
                    .accessibilityLabel("前往第 \(page + 1) 页")
                    .accessibilityAddTraits(page == currentPage ? .isSelected : [])
                }
            }
            .animation(reduceMotion ? nil : DSAnimation.snappy, value: currentPage)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    if currentPage > 0 { backButton }
                    primaryButton
                }
                VStack(spacing: 8) {
                    primaryButton
                    if currentPage > 0 { backButton }
                }
            }


        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 20)
        .padding(.top, 11)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var backButton: some View {
        Button {
            move(to: currentPage - 1)
        } label: {
            Label("返回", systemImage: "chevron.left")
                .frame(minWidth: 76)
        }
        .buttonStyle(.dsAction(.secondary))
        .disabled(currentPage == 0)
        .opacity(currentPage == 0 ? 0 : 1)
        .accessibilityHidden(currentPage == 0)
        .accessibilityIdentifier("welcome.back")
    }

    private var primaryButton: some View {
        Button {
            if currentPage == pageCount - 1 {
                Haptics.impact(.medium)
                onBegin()
            } else {
                move(to: currentPage + 1)
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentPage == pageCount - 1 ? "开始我的旅程" : "继续")
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsActionPrimary)
        .accessibilityIdentifier(currentPage == pageCount - 1 ? "welcome.begin" : "welcome.next")
    }

    private func move(to page: Int) {
        let destination = min(max(page, 0), pageCount - 1)
        guard destination != currentPage else { return }
        Haptics.selection()
        if reduceMotion {
            selectedPage = destination
        } else {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.92)) {
                selectedPage = destination
            }
        }
    }
}

private struct WelcomePageShell<Demo: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    let isActive: Bool
    @ViewBuilder let demo: () -> Demo

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { viewport in
          ScrollView(.vertical) {
            VStack(spacing: 26) {
                demo()
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : min(350, max(230, viewport.size.height * 0.53)))
                    .frame(maxWidth: 560)

                VStack(spacing: 14) {
                    Text(eyebrow)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.dsSkyDeep)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text(title)
                        .font(.system(.title, design: .rounded, weight: .black))
                        .tracking(-0.45)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.dsBrandInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(detail)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 510)
                }
                .opacity(isActive ? 1 : 0.76)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .frame(minHeight: viewport.size.height, alignment: .center)
          }
          .scrollIndicators(.hidden)
          .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct WelcomeCityScreen: View {
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        WelcomeProductFrame(accent: .dsSky, accessibilityLabel: "伦敦城市页概念展示") {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.dsSkyDeep)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("伦敦 · London")
                            .font(.caption.weight(.bold))
                        Text("周六 16:40 · 12°C")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("正在发生", systemImage: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.dsSkyDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.dsSky.opacity(0.11), in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        if let sceneURL = Bundle.main.url(forResource: "london_exterior", withExtension: "jpg"),
                           let sceneImage = UIImage(contentsOfFile: sceneURL.path) {
                            Image(uiImage: sceneImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .scaleEffect(reduceMotion || !isActive ? 1 : 1.035)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: isActive)
                                .accessibilityHidden(true)
                        } else {
                            LinearGradient(
                                colors: [Color.dsSky.opacity(0.7), Color.dsTravelNavy],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .accessibilityHidden(true)
                        }

                        LinearGradient(
                            colors: [.clear, Color.dsTravelNavy.opacity(0.58)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .accessibilityHidden(true)

                        HStack(alignment: .bottom, spacing: 10) {
                            AvatarBadge(
                                name: "Oliver Bennett",
                                size: 58,
                                imageName: "avatar_oliver"
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("城市活动")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Text("去街头走走，遇见新朋友")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Label("外出探索", systemImage: "figure.walk")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.dsSkyDeep)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .background(Color.dsSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(12)
                        .offset(y: reduceMotion || isActive ? 0 : 14)
                        .opacity(isActive ? 1 : 0.15)
                        .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.9), value: isActive)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
                .frame(maxHeight: .infinity)

                WelcomeMiniTabBar(selected: 2)
            }
        }
    }
}

// Render shared production components at a consistent device-space scale.
private struct WelcomeDeviceCanvas<Content: View>: View {
    var minimumHeight: CGFloat = 0
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 390,
                            minimumHeight > 0 ? geometry.size.height / minimumHeight : .infinity)
            content()
                .frame(width: 390, height: geometry.size.height / scale)
                .environment(\.dynamicTypeSize, .medium)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: (geometry.size.width - 390 * scale) / 2)
        }
        .clipped()
    }
}

private struct WelcomeChatHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.left").foregroundStyle(Color.dsSky)
            Spacer(minLength: 0)
            ChatTitleView(title: "Ruby", subtitle: "在线 · 墨尔本 17:20") {
                AvatarBadge(name: "Ruby Walker", size: 32, imageName: "avatar_ruby")
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(Color.dsSuccess).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color.dsSurface, lineWidth: 1.5))
                    }
            }
            Spacer(minLength: 0)
            Image(systemName: "phone.fill")
            Image(systemName: "ellipsis.circle")
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }
}

/// Mirrors ChatComposerSection's idle state; no draft, microphone or account mutation.
private struct WelcomeChatComposer: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic").font(.system(size: 22)).frame(width: 32)
            Text("用英语说点什么…").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.dsBubbleIncoming, in: RoundedRectangle(cornerRadius: DSRadius.bubble))
            Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Color.dsSky.opacity(0.4))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

private struct WelcomeChatMessage: View {
    let text: String
    var outgoing = false
    var body: some View {
        MessageBubble(side: outgoing ? .outgoing : .incoming, leadingAccessory: {
            if !outgoing {
                AvatarBadge(name: "Ruby Walker", size: 28, imageName: "avatar_ruby")
            }
        }) {
            Text(text).font(.body)
        }
    }
}

private struct WelcomeConversationScreen: View {
    let isActive: Bool
    let reduceMotion: Bool
    var body: some View {
        WelcomeProductFrame(accent: .dsBrandCoral, accessibilityLabel: "Ruby 聊天界面概念展示") {
            WelcomeDeviceCanvas {
                VStack(spacing: 0) {
                    WelcomeChatHeader()
                    VStack(spacing: 12) {
                        Text("17:20 · 墨尔本").font(.caption2).foregroundStyle(.secondary)
                        WelcomeChatMessage(text: "How did your presentation go?")
                        WelcomeChatMessage(text: "Much better! I felt more confident.", outgoing: true)
                        WelcomeChatMessage(text: "You said you were nervous last time. What helped?")
                    }
                    .padding(12)
                    .frame(maxHeight: .infinity)
                    WelcomeChatComposer()
                }
                .background(Color.dsBackground)
            }
        }
    }
}

private struct WelcomeDictionaryScreen: View {
    let dictionary: DictDatabase
    let grammar: GrammarPointStore
    var body: some View {
        WelcomeProductFrame(accent: .dsSky, accessibilityLabel: "聊天中打开真实单词卡片") {
            WelcomeDeviceCanvas(minimumHeight: 370) {
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        WelcomeChatHeader()
                        WelcomeChatMessage(text: "Are you a spontaneous person?")
                            .padding(12)
                        Spacer(minLength: 0)
                        WelcomeChatComposer()
                    }
                    .background(Color.dsBackground)
                    DictCardPreview(target: .word("spontaneous"), dictionary: dictionary, grammar: grammar,
                        translations: ["spontaneous laughter": "自然而然的笑声", "spontaneous combustion": "自燃"])
                        .padding(.bottom, 12)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct WelcomePersonalizedScreen: View {
    let isActive: Bool
    let reduceMotion: Bool
    // Read the production starter catalog; do not invent profile fields for marketing.
    private struct Catalog: Decodable { let characters: [CharacterCard] }
    private static let oliver: CharacterCard? = {
        guard let url = Bundle.main.url(forResource: "main_characters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return nil }
        return catalog.characters.first { $0.regionID == "london" }
    }()

    var body: some View {
        WelcomeProductFrame(accent: .dsCyan, accessibilityLabel: "AI 旅伴 Oliver 资料预览") {
            WelcomeDeviceCanvas(minimumHeight: 400) {
                VStack(spacing: 8) {
                    Text("认识 AI 旅伴 · Oliver").font(.subheadline.bold())
                    if let card = Self.oliver {
                        StarterPortraitCard(card: card, city: "伦敦", flag: "🇬🇧", compact: true)
                    }
                    Text("伦敦的 AI 旅伴")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding(14)
            }
        }
    }
}

private struct WelcomeProductFrame<Content: View>: View {
    let accent: Color
    let accessibilityLabel: String
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.dsSurface)

            content()
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.46), Color.white.opacity(colorScheme == .dark ? 0.08 : 0.76)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: accent.opacity(colorScheme == .dark ? 0.18 : 0.13), radius: 22, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct WelcomeMiniTabBar: View {
    let selected: Int

    private var tabs: [(String, String)] {
        var items = [
        ("信息", "bubble.left.and.bubble.right"),
        ("联系人", "person.2"),
        ("活动", "figure.walk"),
        ("我的", "person"),
        ]
        #if DEBUG
        items.append(("测试", "heart.text.square"))
        #endif
        return items
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    VStack(spacing: 2) {
                        Image(systemName: tab.1)
                        Text(tab.0)
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(index == selected ? Color.dsSkyDeep : .secondary)
                    .frame(width: proxy.size.width / CGFloat(tabs.count), height: proxy.size.height)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("welcome.preview.tab.\(index)")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: 39)
        .font(.system(size: 12, weight: .semibold))
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct WelcomeBackdrop: View {
    let colorScheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.dsBackground
                RadialGradient(colors: [Color.dsSky.opacity(0.24), .clear],
                               center: .topLeading, startRadius: 0, endRadius: geometry.size.height * 0.7)
                RadialGradient(colors: [Color.dsBrandCoral.opacity(0.13), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: geometry.size.height * 0.65)
                // 静止的等高线：保留旅行感，不干扰阅读或减少动态效果设置。
                ForEach(0..<5) { index in
                    Ellipse()
                        .stroke(Color.dsSky.opacity(colorScheme == .dark ? 0.10 : 0.09), lineWidth: 1)
                        .frame(width: geometry.size.width * 1.6 + CGFloat(index * 60),
                               height: geometry.size.height * 0.72 + CGFloat(index * 80))
                        .rotationEffect(.degrees(-32))
                        .offset(x: geometry.size.width * 0.45, y: -geometry.size.height * 0.12)
                }
            }
        }
    }
}
