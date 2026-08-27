import CoreKit
import DesignSystem
import DictKit
import DomainKit
import SwiftUI

struct LocalGrammarAnalysisItem: Sendable, Identifiable {
    let id: String
    let point: GrammarPoint
    let matchedText: String
}

struct GrammarAnalysisRequest: Sendable, Identifiable {
    let id: UUID
    let sentence: String
    let learnerLevel: String
    let localItems: [LocalGrammarAnalysisItem]

    var requiresAIFallback: Bool { localItems.isEmpty }
}

/// 整句语法解析：本地规则有命中时直接展示全部结果，零命中时才请求 AI。
struct GrammarAnalysisSheet: View {
    let request: GrammarAnalysisRequest
    let service: GrammarAnalysisService
    let initialAIAnalysis: AIGrammarAnalysis?
    let dictionary: DictDatabase
    let grammar: GrammarPointStore
    let onSpeak: (@MainActor (String) -> Void)?
    let favoriteActions: WordFavoriteActions?
    let aiFallback: (@Sendable (String) async -> String?)?
    let onAIAnalysis: @MainActor (AIGrammarAnalysis) -> Void

    @State private var aiAnalysis: AIGrammarAnalysis?
    @State private var isLoadingAI = false
    @State private var errorMessage: String?
    @State private var wordSelection: TokenSelection?
    @Environment(\.dismiss) private var dismiss

    init(
        request: GrammarAnalysisRequest,
        service: GrammarAnalysisService,
        initialAIAnalysis: AIGrammarAnalysis? = nil,
        dictionary: DictDatabase,
        grammar: GrammarPointStore,
        onSpeak: (@MainActor (String) -> Void)? = nil,
        favoriteActions: WordFavoriteActions? = nil,
        aiFallback: (@Sendable (String) async -> String?)? = nil,
        onAIAnalysis: @escaping @MainActor (AIGrammarAnalysis) -> Void = { _ in }
    ) {
        self.request = request
        self.service = service
        self.initialAIAnalysis = initialAIAnalysis
        self.dictionary = dictionary
        self.grammar = grammar
        self.onSpeak = onSpeak
        self.favoriteActions = favoriteActions
        self.aiFallback = aiFallback
        self.onAIAnalysis = onAIAnalysis
        _aiAnalysis = State(initialValue: initialAIAnalysis)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sentenceCard
                    if request.localItems.isEmpty {
                        aiContent
                    } else {
                        localContent
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.dsBackground)
            .navigationTitle("语法解析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .wordLookupOverlay(
            selection: $wordSelection,
            dictionary: dictionary,
            grammar: grammar,
            onSpeak: onSpeak,
            favoriteActions: favoriteActions,
            aiFallback: aiFallback
        )
        .task(id: request.id) {
            guard request.requiresAIFallback, aiAnalysis == nil else { return }
            await loadAIAnalysis()
        }
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("原句", systemImage: "text.quote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            lookupText(
                request.sentence,
                contextID: "grammar-\(request.id.uuidString)-sentence"
            )
                .font(.body)
                .lineSpacing(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: DSRadius.inline))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.inline)
                .stroke(Color.dsBorder, lineWidth: 1)
        }
    }

    private var localContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sourceHeader(
                title: "本地识别到 \(request.localItems.count) 个语法结构",
                detail: "离线解析",
                systemImage: "checkmark.seal.fill",
                tint: .dsSuccess
            )
            ForEach(Array(request.localItems.enumerated()), id: \.element.id) { index, item in
                localPointCard(item, number: index + 1)
            }
        }
    }

    @ViewBuilder
    private var aiContent: some View {
        if let aiAnalysis {
            VStack(alignment: .leading, spacing: 12) {
                sourceHeader(
                    title: "AI 补充解析",
                    detail: "本地库未命中 · 仅供学习参考",
                    systemImage: "sparkles",
                    tint: .dsSky
                )
                Text(aiAnalysis.summaryZh)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(Array(aiAnalysis.points.enumerated()), id: \.offset) { index, point in
                    aiPointCard(point, number: index + 1)
                }
            }
        } else if isLoadingAI {
            VStack(spacing: 12) {
                BrandMascotView(pose: .coach, size: 54, showsShadow: false)
                ProgressView("咕咕正在分析句子…")
                    .font(.subheadline)
                Text("本地规则未命中，正在调用 AI 补充解析")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label(errorMessage ?? "暂时无法完成解析", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("重新解析") {
                    Task { await loadAIAnalysis() }
                }
                .buttonStyle(.dsAction(.tinted(.dsSky), fullWidth: false, compact: true))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourceHeader(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Spacer(minLength: 8)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func localPointCard(_ item: LocalGrammarAnalysisItem, number: Int) -> some View {
        grammarCard(number: number, title: item.point.title) {
            quote(
                item.matchedText,
                contextID: "grammar-\(request.id.uuidString)-local-\(item.id)-quote"
            )
            Text(item.point.explanationZh)
                .font(.subheadline)
            if let example = item.point.examples.first {
                Divider()
                lookupText(
                    example.en,
                    contextID: "grammar-\(request.id.uuidString)-local-\(item.id)-example"
                )
                    .font(.footnote.weight(.medium))
                Text(example.zh)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func aiPointCard(_ point: AIGrammarAnalysis.Point, number: Int) -> some View {
        grammarCard(number: number, title: point.title) {
            quote(
                point.quote,
                contextID: "grammar-\(request.id.uuidString)-ai-\(number)-quote"
            )
            lookupText(
                point.pattern,
                contextID: "grammar-\(request.id.uuidString)-ai-\(number)-pattern"
            )
                .font(.footnote.monospaced())
                .foregroundStyle(Color.dsSkyDeep)
            Text(point.explanationZh)
                .font(.subheadline)
            Label(point.learnerTipZh, systemImage: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func grammarCard<Content: View>(
        number: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.dsSky, in: Circle())
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: DSRadius.inline))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.inline)
                .stroke(Color.dsSky.opacity(0.18), lineWidth: 1)
        }
    }

    private func quote(_ text: String, contextID: String) -> some View {
        lookupText(text, contextID: contextID)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.dsSkyDeep)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.dsSky.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func lookupText(_ text: String, contextID: String) -> some View {
        TappableText(
            tokens: TokenCache.tokens(for: text, cacheKey: contextID),
            contextID: contextID,
            selection: wordSelection,
            onSelect: { wordSelection = $0 }
        )
    }

    @MainActor
    private func loadAIAnalysis() async {
        guard !isLoadingAI else { return }
        isLoadingAI = true
        errorMessage = nil
        do {
            let analysis = try await service.analyze(
                sentence: request.sentence,
                learnerLevel: request.learnerLevel
            )
            aiAnalysis = analysis
            onAIAnalysis(analysis)
        } catch {
            errorMessage = "AI 解析失败，请检查网络后重试"
        }
        isLoadingAI = false
    }
}
