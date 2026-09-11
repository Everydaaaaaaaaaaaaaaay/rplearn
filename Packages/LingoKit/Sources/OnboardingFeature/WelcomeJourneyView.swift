import CoreKit
import DesignSystem
import SwiftUI
import UIKit

/// 首次启动的品牌入口：用真实运行截图介绍旅程，再进入学习档案。
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
                            eyebrow: "走进城市生活",
                            title: "在日常的街角，\n遇见新故事。",
                            detail: "去公园走走，在咖啡馆歇脚。一次普通的外出，也能成为故事的开始。",
                            accessibilityID: "welcome.page.city"
                        ) {
                            WelcomeScreenshot(name: "activity", label: "应用中的外出活动")
                        }

                        page(
                            index: 1,
                            eyebrow: "会记住你的 AI 旅伴",
                            title: "对话结束，\n关系不会归零。",
                            detail: "旅伴会记住你说过的话、共同经历的故事，也会保留自己的性格。",
                            accessibilityID: "welcome.page.companion"
                        ) {
                            WelcomeScreenshot(name: "chat", label: "与 Ruby 的真实聊天界面")
                        }

                        page(
                            index: 2,
                            eyebrow: "随时点词",
                            title: "不懂就点，\n理解不用离开情境。",
                            detail: "在资料、剧情和聊天里直接查看释义、发音与例句，学完继续聊。",
                            accessibilityID: "welcome.page.dictionary"
                        ) {
                            WelcomeScreenshot(name: "dictionary", label: "聊天中点击单词查看词典")
                        }

                        page(
                            index: 3,
                            eyebrow: "你的第一位旅伴",
                            title: "从一句 Hello，\n认识一个新朋友。",
                            detail: "伦敦、墨尔本、纽约。选一位合拍的旅伴，按自己的节奏开始。",
                            accessibilityID: "welcome.page.personalized"
                        ) {
                            WelcomeScreenshot(name: "companion", label: "选择第一位旅伴的应用界面")
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

private struct WelcomeScreenshot: View {
    let name: String
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("welcome-\(name)-\(colorScheme == .dark ? "dark" : "light")")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            }
            .shadow(color: Color.dsSkyDeep.opacity(0.12), radius: 20, y: 10)
            .frame(maxWidth: 350)
            .accessibilityLabel(label)
            .accessibilityIdentifier("welcome.screenshot.\(name)")
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
