import SwiftUI

public extension View {
    /// Own the header geometry and focus together: native minimized search can retain
    /// an expanded toolbar item after dismissal on iOS 27.
    func dsSceneSearch(text: Binding<String>, title: String, prompt: String) -> some View {
        modifier(DSSceneSearchModifier(text: text, title: title, prompt: prompt))
    }
}

private struct DSSceneSearchModifier: ViewModifier {
    @Binding var text: String
    let title: String
    let prompt: String

    @State private var isPresented = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Keep the inset on one container rather than distributing it through a
        // scene's ZStack children, where a ScrollView can cover the header's hit area.
        VStack(spacing: 0) {
            content
        }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.top, 4)
                    .padding(.bottom, DSSpacing.sm)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isFocused {
                    HStack {
                        Spacer()
                        Button {
                            isFocused = false
                        } label: {
                            Label("收起键盘", systemImage: "keyboard.chevron.compact.down")
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .dsSceneGlass(radius: 22, legibility: .enhanced)
                        }
                        .accessibilityIdentifier("sceneSearch.dismissKeyboard")
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, 6)
                }
            }
            .onDisappear {
                isFocused = false
                isPresented = false
                text = ""
            }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if isPresented {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    TextField(prompt, text: $text)
                        .focused($isFocused)
                        .submitLabel(.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { isFocused = false }
                        .accessibilityIdentifier("sceneSearch.field")
                        .task {
                            // This task belongs to the field; removing it cancels pending focus.
                            guard !Task.isCancelled, isPresented else { return }
                            isFocused = true
                        }
                    if !text.isEmpty {
                        Button { text = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, text.isEmpty ? 14 : 0)
                .frame(maxWidth: .infinity, minHeight: 44)
                .dsSceneGlass(radius: 22)
            } else {
                // Balance the trailing button so the title stays centered.
                Color.clear.frame(width: 44, height: 44)
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }

            Button {
                if isPresented {
                    isFocused = false
                    text = ""
                }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isPresented.toggle()
                }
            } label: {
                Image(systemName: isPresented ? "xmark" : "magnifyingglass")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .dsSceneGlass(radius: 22, interactive: true)
            }
            .accessibilityLabel(isPresented ? "关闭搜索" : prompt)
            .accessibilityIdentifier(isPresented ? "sceneSearch.close" : "sceneSearch.open")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.dsSceneTextPrimary)
    }
}
