import CoreKit
import DesignSystem
import SwiftUI
import UIKit

/// 首次启动的品牌入口：用可操作的产品界面缩影介绍旅程，再进入学习档案。
public struct WelcomeJourneyView: View {
    let onBegin: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPage: Int? = 0

    private let pageCount = 4

    public init(onBegin: @escaping () -> Void) {
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
                            eyebrow: "真实城市剧情",
                            title: "不是背单词，\n是走进故事。",
                            detail: "在城市与生活场景中做出选择，让英语成为真正发生的事。",
                            accessibilityID: "welcome.page.city"
                        ) {
                            WelcomeCityScreen(isActive: currentPage == 0, reduceMotion: reduceMotion)
                        }

                        page(
                            index: 1,
                            eyebrow: "会记住你的 AI 旅伴",
                            title: "对话结束，\n关系不会归零。",
                            detail: "旅伴会记住你说过的话、共同经历的故事，也会保留自己的性格。",
                            accessibilityID: "welcome.page.companion"
                        ) {
                            WelcomeConversationScreen(isActive: currentPage == 1, reduceMotion: reduceMotion)
                        }

                        page(
                            index: 2,
                            eyebrow: "随时点词",
                            title: "不懂就点，\n理解不用离开情境。",
                            detail: "在资料、剧情和聊天里直接查看释义、发音与例句，学完继续聊。",
                            accessibilityID: "welcome.page.dictionary"
                        ) {
                            WelcomeDictionaryScreen(isActive: currentPage == 2, reduceMotion: reduceMotion)
                        }

                        page(
                            index: 3,
                            eyebrow: "为你实时适配",
                            title: "从刚好的难度，\n开始真实开口。",
                            detail: "表达难度会随你的水平与表现调整，你只需要选择第一位旅伴。",
                            accessibilityID: "welcome.page.personalized"
                        ) {
                            WelcomePersonalizedScreen(isActive: currentPage == 3, reduceMotion: reduceMotion)
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

            Text("\(currentPage + 1) / \(pageCount)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.dsSkyDeep)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.dsSurface.opacity(0.76), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.dsSky.opacity(0.16), lineWidth: 1)
                }
                .accessibilityLabel("第 \(currentPage + 1) 页，共 \(pageCount) 页")
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
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { page in
                    Button {
                        move(to: page)
                    } label: {
                        Capsule()
                            .fill(page == currentPage ? Color.dsSky : Color.dsBorder)
                            .frame(width: page == currentPage ? 25 : 7, height: 7)
                            .contentShape(Rectangle().inset(by: -8))
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
                    backButton
                    primaryButton
                }
                VStack(spacing: 8) {
                    primaryButton
                    backButton
                }
            }

            if currentPage == 0 {
                Text("向左滑动，也可以继续浏览")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 20)
        .padding(.top, 11)
        .padding(.bottom, 7)
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
        ScrollView(.vertical) {
            VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 16) {
                demo()
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 360 : 350)
                    .frame(maxWidth: 560)

                VStack(spacing: 8) {
                    Text(eyebrow)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.dsSkyDeep)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text(title)
                        .font(.system(.title, design: .rounded, weight: .black))
                        .tracking(-0.45)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.dsBrandInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(detail)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 510)
                }
                .opacity(isActive ? 1 : 0.76)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct WelcomeCityScreen: View {
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        WelcomeProductFrame(accent: .dsSky, accessibilityLabel: "伦敦城市页实机界面示例") {
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
                                Text("旧书店的晚间朗读")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Text("Oliver 正在等你开口")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Label("进入故事", systemImage: "arrow.right.circle.fill")
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

                WelcomeMiniTabBar(selected: 0)
            }
        }
    }
}

private struct WelcomeConversationScreen: View {
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        WelcomeProductFrame(accent: .dsBrandCoral, accessibilityLabel: "Ruby 对话页实机界面示例") {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    AvatarBadge(name: "Ruby Walker", size: 34, imageName: "avatar_ruby")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Ruby Walker")
                            .font(.caption.weight(.bold))
                        HStack(spacing: 4) {
                            Circle().fill(Color.dsSuccess).frame(width: 5, height: 5)
                            Text("刚刚在线 · 墨尔本")
                        }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "phone.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dsSkyDeep)
                        .frame(width: 28, height: 28)
                        .background(Color.dsSky.opacity(0.1), in: Circle())
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Divider() }

                VStack(spacing: 8) {
                    WelcomeMessageBubble(
                        text: "The tide's perfect this arvo. Want to join?",
                        isOutgoing: false,
                        delay: 0,
                        isActive: isActive,
                        reduceMotion: reduceMotion
                    )
                    WelcomeMessageBubble(
                        text: "Save me a board? I'll be there at five.",
                        isOutgoing: true,
                        delay: 0.05,
                        isActive: isActive,
                        reduceMotion: reduceMotion
                    )
                    WelcomeMessageBubble(
                        text: "Deal. And I remembered—you prefer the quiet end of the beach.",
                        isOutgoing: false,
                        delay: 0.1,
                        isActive: isActive,
                        reduceMotion: reduceMotion
                    )

                    Label("她记得：你更喜欢安静的地方", systemImage: "brain.head.profile.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.dsBrandCoral)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.dsBrandCoral.opacity(0.09), in: Capsule())
                        .opacity(isActive ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.18) : .easeOut(duration: 0.28).delay(0.14), value: isActive)
                }
                .padding(11)
                .frame(maxHeight: .infinity)

                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.dsSkyDeep)
                    Text("用英语回复 Ruby…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.dsSky, in: Circle())
                }
                .padding(8)
                .background(Color.dsSurfaceMuted, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(10)
            }
        }
    }
}

private struct WelcomeDictionaryScreen: View {
    let isActive: Bool
    let reduceMotion: Bool

    @State private var showsDefinition = true

    var body: some View {
        WelcomeProductFrame(accent: .dsQuiz, accessibilityLabel: "资料页点词与单词弹窗实机界面示例") {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    AvatarBadge(name: "Oliver Bennett", size: 32, imageName: "avatar_oliver")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Oliver 的资料")
                            .font(.caption.weight(.bold))
                        Text("性格与表达方式")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Divider() }

                VStack(alignment: .leading, spacing: 7) {
                    Text("HOW HE SPEAKS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)

                    HStack(spacing: 3) {
                        Text("Dry humour, but surprisingly")
                        Button {
                            withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                                showsDefinition.toggle()
                            }
                        } label: {
                            Text("spontaneous")
                                .fontWeight(.bold)
                                .foregroundStyle(Color.dsQuiz)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.dsQuiz.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("单词 spontaneous，轻点查看释义")
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                    Text("He often turns a simple invitation into a playful challenge.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                if showsDefinition {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("spontaneous")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                            Text("/spɒnˈteɪ.ni.əs/")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(Color.dsQuiz)
                        }
                        Text("adj. 自发的；自然流露的")
                            .font(.system(size: 11, weight: .bold))
                        Text("It was a spontaneous trip to the coast.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack {
                            Label("已匹配当前语境", systemImage: "checkmark.circle.fill")
                            Spacer()
                            Label("收藏", systemImage: "bookmark")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.dsQuiz)
                    }
                    .padding(12)
                    .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Color.dsQuiz.opacity(0.2), lineWidth: 1)
                    }
                    .shadow(color: Color.dsQuiz.opacity(0.13), radius: 16, y: 7)
                    .padding(11)
                    .offset(y: reduceMotion || isActive ? 0 : 18)
                    .opacity(isActive ? 1 : 0.08)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.4, dampingFraction: 0.92), value: isActive)
                } else {
                    Label("轻点高亮单词，立即查看释义", systemImage: "hand.tap.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.dsQuiz)
                        .padding(.bottom, 24)
                }
            }
        }
    }
}

private struct WelcomePersonalizedScreen: View {
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        WelcomeProductFrame(accent: .dsCyan, accessibilityLabel: "个性化学习档案与旅伴选择实机界面示例") {
            VStack(spacing: 11) {
                HStack(alignment: .top, spacing: 10) {
                    BrandMascotView(pose: .guide, size: 52, showsShadow: false)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("你的第一段旅程")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                        Text("根据当前水平实时调整")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("B1")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Color.dsSkyDeep)
                        .frame(width: 40, height: 40)
                        .background(Color.dsSky.opacity(0.12), in: Circle())
                }

                VStack(spacing: 8) {
                    WelcomeSettingRow(icon: "textformat", title: "表达难度", value: "生活交流")
                    Divider().padding(.leading, 30)
                    WelcomeSettingRow(icon: "waveform", title: "开口辅助", value: "需要时出现")
                    Divider().padding(.leading, 30)
                    WelcomeSettingRow(icon: "arrow.triangle.2.circlepath", title: "动态调整", value: "已开启")
                }
                .padding(10)
                .background(Color.dsSurfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("选择第一位旅伴")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        WelcomeCompanionChoice(name: "Oliver", city: "伦敦", imageName: "avatar_oliver", isSelected: true)
                        WelcomeCompanionChoice(name: "Ruby", city: "墨尔本", imageName: "avatar_ruby", isSelected: false)
                        WelcomeCompanionChoice(name: "Marcus", city: "纽约", imageName: "avatar_marcus", isSelected: false)
                    }
                    .frame(maxWidth: .infinity)
                }

                Label("所有选择之后都能修改", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.dsCyan)
                    .opacity(isActive ? 1 : 0)
                    .scaleEffect(reduceMotion || isActive ? 1 : 0.9)
                    .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.4, dampingFraction: 0.86).delay(0.1), value: isActive)
            }
            .padding(13)
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

private struct WelcomeMessageBubble: View {
    let text: String
    let isOutgoing: Bool
    let delay: Double
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: 42) }
            Text(text)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(isOutgoing ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    isOutgoing ? Color.dsSky : Color.dsBubbleIncoming,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            if !isOutgoing { Spacer(minLength: 42) }
        }
        .offset(y: reduceMotion || isActive ? 0 : 12)
        .opacity(isActive ? 1 : 0.12)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.16)
                : .spring(response: 0.38, dampingFraction: 0.94).delay(delay),
            value: isActive
        )
    }
}

private struct WelcomeMiniTabBar: View {
    let selected: Int

    private let tabs = [
        ("城市", "building.2.fill"),
        ("消息", "bubble.left.and.bubble.right.fill"),
        ("我的", "person.crop.circle.fill"),
    ]

    var body: some View {
        HStack {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                VStack(spacing: 2) {
                    Image(systemName: tab.1)
                    Text(tab.0)
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(index == selected ? Color.dsSkyDeep : .secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct WelcomeSettingRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.dsCyan)
                .frame(width: 22, height: 22)
                .background(Color.dsCyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct WelcomeCompanionChoice: View {
    let name: String
    let city: String
    let imageName: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            AvatarBadge(name: name, size: 48, imageName: imageName)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.dsSky, lineWidth: 2.5)
                            .padding(-3)
                    }
                }
            Text(name)
                .font(.system(size: 9, weight: .bold))
            Text(city)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(isSelected ? Color.dsSky.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct WelcomeBackdrop: View {
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            Color.dsBackground

            LinearGradient(
                colors: [
                    Color.dsSky.opacity(colorScheme == .dark ? 0.14 : 0.1),
                    Color.dsBackground.opacity(0.25),
                    Color.dsQuiz.opacity(colorScheme == .dark ? 0.07 : 0.035),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.dsCyan.opacity(0.1), .clear],
                center: UnitPoint(x: 0.93, y: 0.12),
                startRadius: 8,
                endRadius: 245
            )

            RadialGradient(
                colors: [Color.dsBrandCoral.opacity(0.055), .clear],
                center: UnitPoint(x: 0.03, y: 0.75),
                startRadius: 5,
                endRadius: 230
            )
        }
    }
}
