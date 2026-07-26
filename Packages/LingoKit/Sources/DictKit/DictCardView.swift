import CoreKit
import DesignSystem
import SwiftUI

/// 词典卡内容目标：单词或语法点，卡内栈式跳转（原信息替换显示）。
public enum DictTarget: Hashable, Sendable {
    case word(String)
    case grammarPoint(String)
}

/// 词典浮窗卡片：释义/音标/考试标签/语法点，卡内词与 related 可继续点击跳转。
public struct DictCardView: View {
    private let dictionary: DictDatabase
    private let grammar: GrammarPointStore
    private let onSpeak: (@MainActor (String) -> Void)?
    private let aiFallback: (@Sendable (String) async -> String?)?
    private let onDismiss: (@MainActor () -> Void)?

    @State private var path: [DictTarget]
    @State private var entry: DictEntry?
    @State private var grammarPoints: [GrammarPoint] = []
    @State private var isLoading = true
    @State private var aiExplanation: String?
    @State private var isLoadingAI = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        target: DictTarget,
        dictionary: DictDatabase,
        grammar: GrammarPointStore,
        onSpeak: (@MainActor (String) -> Void)? = nil,
        aiFallback: (@Sendable (String) async -> String?)? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        _path = State(initialValue: [target])
        self.dictionary = dictionary
        self.grammar = grammar
        self.onSpeak = onSpeak
        self.aiFallback = aiFallback
        self.onDismiss = onDismiss
    }

    private var currentTarget: DictTarget? { path.last }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color.dsSurface)
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(Color.dsBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .task(id: path) {
            await loadCurrentTarget()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if path.count > 1 {
                Button {
                    _ = path.popLast()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.borderless)
            }
            switch currentTarget {
            case .word(let word):
                Text(entry?.word ?? word)
                    .font(.headline)
                if let phonetic = entry?.phonetic {
                    Text("/\(phonetic)/")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let onSpeak {
                    Button {
                        onSpeak(entry?.word ?? word)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                }
            case .grammarPoint(let id):
                Text(grammar.point(id: id)?.title ?? "语法点")
                    .font(.headline)
                    .lineLimit(1)
            case nil:
                EmptyView()
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("关闭释义")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch currentTarget {
        case .word(let word):
            wordContent(word)
        case .grammarPoint(let id):
            if let point = grammar.point(id: id) {
                grammarContent(point)
            } else {
                Text("未找到该语法点")
                    .foregroundStyle(.secondary)
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func wordContent(_ word: String) -> some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let entry {
            if !entry.tags.isEmpty || entry.oxford || entry.collins > 0 {
                tagChips(entry)
            }
            ForEach(entry.translationLines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
            }
            let points = grammarPointsToShow(for: word)
            if !points.isEmpty {
                Divider()
                ForEach(points) { point in
                    grammarSummary(point)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("词典未收录该词", systemImage: "book.closed")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                if let aiExplanation {
                    Text(aiExplanation)
                        .font(.subheadline)
                    Text("AI 生成，仅供参考（非词典权威）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if aiFallback != nil {
                    Button {
                        requestAIExplanation(word)
                    } label: {
                        if isLoadingAI {
                            ProgressView()
                        } else {
                            Label("用 AI 简单解释", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.duo(.tinted(.dsSky), fullWidth: false, compact: true))
                    .disabled(isLoadingAI)
                }
            }
        }
    }

    private func grammarPointsToShow(for word: String) -> [GrammarPoint] {
        grammar.points(forTrigger: word)
    }

    private func tagChips(_ entry: DictEntry) -> some View {
        HStack(spacing: 6) {
            ForEach(DictTagDisplayPolicy.visibleTitles(for: entry), id: \.self) { title in
                chip(title)
            }
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ text: String) -> some View {
        DSChip(text, tint: .dsSky)
    }

    @ViewBuilder
    private func grammarSummary(_ point: GrammarPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(point.title)
                .font(.subheadline.weight(.semibold))
            Text(point.explanationZh)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button("查看详情") {
                path.append(.grammarPoint(point.id))
            }
            .font(.footnote)
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func grammarContent(_ point: GrammarPoint) -> some View {
        Text(point.explanationZh)
            .font(.subheadline)
        ForEach(Array(point.examples.enumerated()), id: \.offset) { _, example in
            VStack(alignment: .leading, spacing: 2) {
                // 例句内的词可继续点击跳转
                TappableText(
                    tokens: WordTokenizer.tokenize(example.en),
                    contextID: "example-\(point.id)",
                    onSelect: { selection in
                        path.append(.word(selection.word))
                    }
                )
                .font(.footnote)
                Text(example.zh)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBubbleIncoming, in: RoundedRectangle(cornerRadius: DSRadius.inline))
        }
        if !point.related.isEmpty {
            HStack(spacing: 8) {
                Text("相关：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(point.related, id: \.self) { relatedID in
                    if let related = grammar.point(id: relatedID) {
                        Button(related.title) {
                            path.append(.grammarPoint(relatedID))
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    // MARK: - 加载

    private func loadCurrentTarget() async {
        guard case .word(let word) = currentTarget else {
            isLoading = false
            return
        }
        isLoading = true
        aiExplanation = nil
        entry = await dictionary.lookup(word)
        grammarPoints = grammar.points(forTrigger: word)
        isLoading = false
    }

    private func requestAIExplanation(_ word: String) {
        guard let aiFallback else { return }
        isLoadingAI = true
        Task {
            aiExplanation = await aiFallback(word) ?? "解释失败，请稍后再试"
            isLoadingAI = false
        }
    }
}
