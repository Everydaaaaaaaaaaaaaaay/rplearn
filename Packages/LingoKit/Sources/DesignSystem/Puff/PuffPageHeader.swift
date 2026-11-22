import SwiftUI

public extension View {
    /// 页面顶部的大标题与搜索。圆形搜索按钮点开后“长”成搜索框，关闭时缩回。
    ///
    /// 隐藏系统导航栏，由本页头同时管理标题、搜索焦点和收起键盘按钮；
    /// 子页面仍使用各自的原生导航栏。
    func puffPageHeader(
        title: String,
        subtitle: String? = nil,
        searchText: Binding<String>,
        searchPrompt: String,
        resetToken: Int = 0
    ) -> some View {
        modifier(PuffPageHeaderModifier(
            title: title,
            subtitle: subtitle,
            text: searchText,
            prompt: searchPrompt,
            resetToken: resetToken
        ))
    }

    /// 没有搜索的页头，可放一个右侧圆形操作按钮。
    ///
    /// `showsBack` 用于推入的子页面：标题左侧放返回按钮，页面不再使用系统导航栏。
    /// 子页面和来源页都隐藏系统栏，转场时不会切换导航栏显隐（切换会让返回途中的按钮漂移、取消返回后顶栏消失）。
    /// 普通 push 进入的页面另加 `dsInteractivePopGesture()` 保留左缘返回；缩放转场自带交互返回，不用加。
    func puffPageHeader(
        title: String,
        subtitle: String? = nil,
        showsBack: Bool = false,
        trailing: PuffHeaderAction? = nil
    ) -> some View {
        modifier(PuffPageHeaderModifier(
            title: title,
            subtitle: subtitle,
            text: nil,
            prompt: "",
            resetToken: 0,
            showsBack: showsBack,
            trailing: trailing
        ))
    }
}

/// 页头右侧的圆形图标按钮。
public struct PuffHeaderAction {
    let systemImage: String
    let label: String
    let identifier: String?
    let action: @MainActor () -> Void

    public init(systemImage: String, label: String, identifier: String? = nil, action: @escaping @MainActor () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.identifier = identifier
        self.action = action
    }
}

private struct PuffPageHeaderModifier: ViewModifier {
    let title: String
    let subtitle: String?
    /// 为 nil 时页头不提供搜索。
    let text: Binding<String>?
    let prompt: String
    let resetToken: Int
    var showsBack = false
    var trailing: PuffHeaderAction?

    @State private var isSearching = false
    @FocusState private var isFocused: Bool
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.puffPageTint) private var tint
    @Environment(\.puffPageCameo) private var cameo

    func body(content: Content) -> some View {
        // 把 inset 放在单一容器上，避免 ZStack 里的滚动视图盖住页头的点击区域。
        VStack(spacing: 0) {
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .padding(.horizontal, Puff.Space.m)
                .padding(.top, 6)
                .padding(.bottom, Puff.Space.s)
                .background(alignment: .top) {
                    headerBackground
                        .padding(.bottom, -10)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isFocused {
                HStack {
                    Spacer()
                    Button {
                        isFocused = false
                    } label: {
                        Label("收起键盘", systemImage: "keyboard.chevron.compact.down")
                            .font(.puff(.subheadline, Puff.Weight.emphasis))
                            .foregroundStyle(Puff.Palette.ink)
                            .padding(.horizontal, Puff.Space.m)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PuffCardButtonStyle(radius: 22, lipHeight: 3))
                    .accessibilityIdentifier("sceneSearch.dismissKeyboard")
                }
                .padding(.horizontal, Puff.Space.m)
                .padding(.vertical, 6)
                .transition(.puffPop)
            }
        }
        .onDisappear { isFocused = false }
        .onChange(of: resetToken) {
            isFocused = false
            isSearching = false
            text?.wrappedValue = ""
        }
    }

    /// 页头底：有页面色调时是与页面背景对齐的天空带（带飘云），底边淡出；否则是白色渐隐。
    @ViewBuilder
    private var headerBackground: some View {
        let fade = LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        if let tint {
            // 只取页头这一截：天空带比页头高，按页头实际大小裁切，底边淡出接上页面背景里的同一条天空带。
            GeometryReader { proxy in
                PuffSkyBand(candy: tint, showsClouds: true)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()
            }
            .mask(fade)
        } else {
            Puff.Palette.page.mask(fade)
        }
    }

    private var searchText: String { text?.wrappedValue ?? "" }

    private var animation: Animation {
        Puff.Motion.resolve(Puff.Motion.bouncy, reduceMotion: reduceMotion)
    }

    private var header: some View {
        HStack(spacing: Puff.Space.s) {
            if isSearching {
                searchField
                    .transition(.opacity)
                closeButton
                    .transition(.puffPop)
            } else {
                if showsBack {
                    PuffBackButton()
                }
                titleBlock
                    .transition(.opacity.combined(with: .offset(x: -12)))
                Spacer(minLength: Puff.Space.xs)
                if let trailing {
                    trailingButton(trailing)
                }
                if text != nil {
                    openButton
                } else if trailing == nil, let cameo {
                    // 页头右侧空着时，吉祥物坐在标题旁边。
                    PuffMascotCameo(cameo.bird, pose: cameo.pose, size: 52)
                        .padding(.vertical, -6)
                }
            }
        }
        .frame(minHeight: 52)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.puff(showsBack ? .title : .largeTitle, Puff.Weight.display))
                .foregroundStyle(Puff.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.puff(.subheadline, Puff.Weight.label))
                    .foregroundStyle(Puff.Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                    .animation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion), value: subtitle)
            }
        }
    }

    private var searchShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var openButton: some View {
        Button {
            withAnimation(animation) { isSearching = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(PuffCandy.sky.deep)
                .frame(width: 46, height: 46)
                .background {
                    searchShape
                        .fill(PuffCandy.sky.wash)
                        .matchedGeometryEffect(id: "search.surface", in: namespace)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.puffSquish)
        .accessibilityLabel(prompt)
        .accessibilityIdentifier("sceneSearch.open")
    }

    private func trailingButton(_ trailing: PuffHeaderAction) -> some View {
        Button(action: trailing.action) {
            Image(systemName: trailing.systemImage)
                .font(.system(size: 18, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(Puff.Palette.inkSoft)
                .frame(width: 46, height: 46)
                .background(Puff.Palette.cloud, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.puffSquish)
        .accessibilityLabel(trailing.label)
        .accessibilityIdentifier(trailing.identifier ?? "")
    }

    private var closeButton: some View {
        Button {
            isFocused = false
            text?.wrappedValue = ""
            withAnimation(animation) { isSearching = false }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(Puff.Palette.inkSoft)
                .frame(width: 46, height: 46)
                .background(Puff.Palette.cloud, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.puffSquish)
        .accessibilityLabel("关闭搜索")
        .accessibilityIdentifier("sceneSearch.close")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(PuffCandy.sky.deep)
            TextField(prompt, text: text ?? .constant(""))
                .font(.puff(.body, Puff.Weight.label))
                .foregroundStyle(Puff.Palette.ink)
                .tint(PuffCandy.sky.base)
                .focused($isFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { isFocused = false }
                .accessibilityIdentifier("sceneSearch.field")
                .task {
                    // 任务属于输入框本身；关闭搜索会取消尚未完成的聚焦。
                    guard !Task.isCancelled, isSearching else { return }
                    isFocused = true
                }
            if !searchText.isEmpty {
                Button {
                    text?.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Puff.Palette.inkFaint)
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.puffSquish)
                .accessibilityLabel("清除搜索")
                .transition(.puffPop)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, searchText.isEmpty ? 14 : 4)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background {
            searchShape
                .fill(PuffCandy.sky.wash)
                .matchedGeometryEffect(id: "search.surface", in: namespace)
        }
        .overlay {
            searchShape
                .strokeBorder(isFocused ? PuffCandy.sky.base : .clear, lineWidth: 2)
        }
        .animation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion), value: searchText.isEmpty)
        .animation(Puff.Motion.resolve(Puff.Motion.press, reduceMotion: reduceMotion), value: isFocused)
    }
}

/// 子页面的返回按钮：白色软圆片、墨色箭头，44pt。默认用环境里的 `dismiss` 返回上一页。
public struct PuffBackButton: View {
    @Environment(\.dismiss) private var dismiss
    private let label: String
    private let action: (@MainActor () -> Void)?

    public init(label: String = "返回", action: (@MainActor () -> Void)? = nil) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button { if let action { action() } else { dismiss() } } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: Puff.Weight.icon, design: .rounded))
                .foregroundStyle(Puff.Palette.ink)
                .frame(width: 44, height: 44)
                .background(Puff.Palette.card, in: Circle())
                .overlay { Circle().strokeBorder(Puff.Palette.line, lineWidth: 1) }
                .shadow(color: Puff.Palette.ink.opacity(0.06), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.puffSquish)
        .accessibilityLabel(label)
    }
}
