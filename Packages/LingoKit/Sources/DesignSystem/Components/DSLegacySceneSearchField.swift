import SwiftUI

/// iOS 18/19/20 的 `.searchable(placement: .toolbar)` 会在摄影背景上退化为
/// 近乎透明的整行搜索框。旧系统直接使用这个稳定材质版本；iOS 26 仍使用
/// 系统紧凑搜索按钮和原生展开动效。
public struct DSLegacySceneSearchField: View {
    @Binding private var text: String
    private let prompt: String
    @FocusState private var isFocused: Bool

    public init(text: Binding<String>, prompt: String) {
        _text = text
        self.prompt = prompt
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.dsTravelNavy.opacity(0.78))

            TextField(prompt, text: $text)
                .focused($isFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.dsTravelNavy)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.dsTravelNavy.opacity(0.66))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(
            Color.dsSurface.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .dsSceneGlass(
            radius: 20,
            tint: Color.white.opacity(0.04),
            interactive: true,
            legibility: .shielded
        )
        .accessibilityElement(children: .contain)
    }
}
