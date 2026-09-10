import DesignSystem
import SwiftUI

public struct GrammarTermSelection: Hashable, Sendable {
    public let contextID: String
    public let segmentID: Int
    public let term: String

    public init(contextID: String, segmentID: Int, term: String) {
        self.contextID = contextID
        self.segmentID = segmentID
        self.term = term
    }
}

public struct SelectedGrammarTermAnchorKey: PreferenceKey {
    public static var defaultValue: Anchor<CGRect>? { nil }

    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// 中文语法讲解中的可点术语。明显的色块和描边用于区分普通正文，最长词优先匹配。
public struct TappableGrammarTermText: View {
    private let segments: [GrammarTermCatalog.Segment]
    private let contextID: String
    private let selection: GrammarTermSelection?
    private let onSelect: (GrammarTermSelection) -> Void

    public init(
        _ text: String,
        contextID: String,
        selection: GrammarTermSelection? = nil,
        onSelect: @escaping (GrammarTermSelection) -> Void
    ) {
        self.segments = GrammarTermCatalog.segments(in: text)
        self.contextID = contextID
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        FlowLayout(spacing: 0, lineSpacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                switch segment {
                case .text(let text):
                    Text(text)
                        .foregroundStyle(.secondary)
                case .term(let term):
                    termButton(term, segmentID: index)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func termButton(_ term: String, segmentID: Int) -> some View {
        let isSelected = selection?.contextID == contextID
            && selection?.segmentID == segmentID
        return Button {
            onSelect(
                GrammarTermSelection(
                    contextID: contextID,
                    segmentID: segmentID,
                    term: term
                )
            )
        } label: {
            Text(term)
                .fontWeight(.bold)
                .foregroundStyle(Color.dsCoach)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(
                    Color.dsCoach.opacity(isSelected ? 0.24 : 0.13),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.dsCoach.opacity(isSelected ? 0.8 : 0.42), lineWidth: 0.75)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("语法术语：\(term)")
        .accessibilityHint("打开定义、用法和例句")
        .anchorPreference(key: SelectedGrammarTermAnchorKey.self, value: .bounds) { anchor in
            isSelected ? anchor : nil
        }
    }
}

public struct GrammarTermLookupOverlayModifier: ViewModifier {
    @Binding var selection: GrammarTermSelection?
    let dictionary: DictDatabase
    let grammar: GrammarPointStore
    let exampleTranslationActions: DictExampleTranslationActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(SelectedGrammarTermAnchorKey.self) { anchor in
                if let selection, let anchor {
                    GeometryReader { proxy in
                        let termRect = proxy[anchor]
                        let cardHeight = DictCardLayout.maximumHeight
                        let halfWidth = DictCardLayout.width / 2
                        let halfHeight = cardHeight / 2
                        let showBelow = termRect.maxY + cardHeight + 12 < proxy.size.height
                        ZStack {
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture { self.selection = nil }
                                .accessibilityHidden(true)
                            DictCardView(
                                target: .grammarTerm(selection.term),
                                dictionary: dictionary,
                                grammar: grammar,
                                exampleTranslationActions: exampleTranslationActions,
                                onDismiss: { self.selection = nil }
                            )
                            .id(selection)
                            .position(
                                x: min(
                                    max(halfWidth + 10, termRect.midX),
                                    proxy.size.width - halfWidth - 10
                                ),
                                y: showBelow
                                    ? termRect.maxY + 8 + halfHeight
                                    : max(halfHeight + 8, termRect.minY - 8 - halfHeight)
                            )
                        }
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .scale(scale: 0.96, anchor: showBelow ? .top : .bottom)
                                    .combined(with: .opacity)
                        )
                    }
                }
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : DSAnimation.snappy,
                value: selection
            )
    }
}

extension View {
    public func grammarTermLookupOverlay(
        selection: Binding<GrammarTermSelection?>,
        dictionary: DictDatabase,
        grammar: GrammarPointStore,
        exampleTranslationActions: DictExampleTranslationActions
    ) -> some View {
        modifier(
            GrammarTermLookupOverlayModifier(
                selection: selection,
                dictionary: dictionary,
                grammar: grammar,
                exampleTranslationActions: exampleTranslationActions
            )
        )
    }
}
