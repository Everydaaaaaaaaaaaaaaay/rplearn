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
}

private struct PuffPageHeaderModifier: ViewModifier {
    let title: String
    let subtitle: String?
    @Binding var text: String
    let prompt: String
    let resetToken: Int

    @State private var isSearching = false
    @FocusState private var isFocused: Bool
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    LinearGradient(
                        stops: [
                            .init(color: Puff.Palette.page, location: 0),
                            .init(color: Puff.Palette.page, location: 0.82),
                            .init(color: Puff.Palette.page.opacity(0), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
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
                            .font(.puff(.subheadline, .heavy))
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
            text = ""
        }
    }

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
                titleBlock
                    .transition(.opacity.combined(with: .offset(x: -12)))
                Spacer(minLength: Puff.Space.xs)
                openButton
            }
        }
        .frame(minHeight: 52)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.puff(.largeTitle, .heavy))
                .foregroundStyle(Puff.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.puff(.subheadline, .bold))
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
                .font(.system(size: 19, weight: .heavy, design: .rounded))
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

    private var closeButton: some View {
        Button {
            isFocused = false
            text = ""
            withAnimation(animation) { isSearching = false }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
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
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(PuffCandy.sky.deep)
            TextField(prompt, text: $text)
                .font(.puff(.body, .semibold))
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
            if !text.isEmpty {
                Button {
                    text = ""
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
        .padding(.trailing, text.isEmpty ? 14 : 4)
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
        .animation(Puff.Motion.resolve(Puff.Motion.pop, reduceMotion: reduceMotion), value: text.isEmpty)
        .animation(Puff.Motion.resolve(Puff.Motion.press, reduceMotion: reduceMotion), value: isFocused)
    }
}
