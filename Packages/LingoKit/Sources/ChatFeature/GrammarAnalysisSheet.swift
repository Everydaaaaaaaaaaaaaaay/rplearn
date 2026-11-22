import CoreKit
import DesignSystem
import DictKit
import DomainKit
import LLMKit
import PersistenceKit
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
}

enum GrammarAnalysisSource: String, Sendable, CaseIterable, Identifiable {
    case local = "本地解析"
    case ai = "AI 解析"

    var id: Self { self }
}

private struct GrammarFavoriteDescriptor: Sendable {
    let id: String
    let title: String
    let explanationZh: String
}

/// 整句语法解析：本地知识库与 AI 是两种独立来源，由用户明确选择。
struct GrammarAnalysisSheet: View {
    let request: GrammarAnalysisRequest
    let service: GrammarAnalysisService
    let initialAIAnalysis: AIGrammarAnalysis?
    let dictionary: DictDatabase
    let grammar: GrammarPointStore
    let favorites: FavoritesStore
    let onSpeak: (@MainActor (String) -> Void)?
    let favoriteActions: WordFavoriteActions?
    let aiFallback: (@Sendable (String) async -> String?)?

    let onAIAnalysis: @MainActor (AIGrammarAnalysis) -> Void

    @State private var model: GrammarAnalysisModel
    @State private var wordSelection: TokenSelection?
    @State private var favoriteGrammarPointIDs: Set<String> = []
    @State private var updatingGrammarPointIDs: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    init(
        request: GrammarAnalysisRequest,
        service: GrammarAnalysisService,
        initialAIAnalysis: AIGrammarAnalysis? = nil,
        dictionary: DictDatabase,
        grammar: GrammarPointStore,
        favorites: FavoritesStore,
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
        self.favorites = favorites
        self.onSpeak = onSpeak
        self.favoriteActions = favoriteActions
        self.aiFallback = aiFallback

        self.onAIAnalysis = onAIAnalysis
        _model = State(initialValue: GrammarAnalysisModel(analysis: initialAIAnalysis))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sentenceCard
                    sourcePicker
                    if model.source == .ai {
                        aiContent
                    } else {
                        localContent
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Puff.Palette.page)
            .fontDesign(.rounded)
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
            aiFallback: aiFallback)
        .task(id: "\(request.id)-\(model.source)-\(model.retryRevision)") {
            guard model.source == .ai else { return }
            let service = service, sentence = request.sentence, level = request.learnerLevel
            if let result = await model.load(using: { try await service.analyze(sentence: sentence, learnerLevel: level) }) {
                onAIAnalysis(result)
            }
        }
        .task(id: request.id) {
            await reloadGrammarFavorites()
        }
    }

    private var sourcePicker: some View {
        Picker("解析来源", selection: $model.source) {
            ForEach(GrammarAnalysisSource.allCases) { source in
                Text(source.rawValue).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("GrammarAnalysisSourcePicker")
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("原句", systemImage: "text.quote")
                .font(.puff(.caption, Puff.Weight.emphasis))
                .foregroundStyle(Puff.Palette.inkSoft)
            lookupText(
                request.sentence,
                contextID: "grammar-\(request.id.uuidString)-sentence"
            )
                .font(.body)
                .lineSpacing(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .puffCard(radius: Puff.Radius.large)
    }

    private var localContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if request.localItems.isEmpty {
                sourceHeader(
                    title: "本地知识库未命中",
                    detail: "离线",
                    systemImage: "books.vertical",
                    tint: Puff.Palette.inkSoft
                )
            } else {
                sourceHeader(
                    title: "本地识别到 \(request.localItems.count) 个语法结构",
                    detail: "离线",
                    systemImage: "checkmark.seal.fill",
                    tint: PuffCandy.mint.deep
                )
                ForEach(Array(request.localItems.enumerated()), id: \.element.id) { index, item in
                    localPointCard(item, number: index + 1)
                }
            }

            Button {
                selectAIAnalysis()
            } label: {
                Label("直接使用 AI 解析", systemImage: "sparkles")
            }
            .buttonStyle(GrammarActionButtonStyle())
            .accessibilityIdentifier("DirectAIGrammarAnalysisButton")
        }
    }

    @ViewBuilder
    private var aiContent: some View {
        if let aiAnalysis = model.analysis {
            VStack(alignment: .leading, spacing: 12) {
                sourceHeader(
                    title: "AI 独立解析",
                    detail: "仅供参考",
                    systemImage: "sparkles",
                    tint: PuffCandy.grape.deep
                )
                Text(aiAnalysis.summaryZh)
                    .font(.puff(.subheadline, Puff.Weight.body))
                    .foregroundStyle(Puff.Palette.inkSoft)
                ForEach(Array(aiAnalysis.points.enumerated()), id: \.offset) { index, point in
                    aiPointCard(point, number: index + 1)
                }
            }
        } else if model.isLoading {
            VStack(spacing: 12) {
                BrandMascotView(pose: .coach, size: 104, showsShadow: false, reactsToTap: true)
                PuffLoadingDots()
                    .accessibilityLabel("嘎嘎正在分析句子")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let errorMessage = model.error {
            VStack(alignment: .leading, spacing: 12) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.puff(.subheadline, Puff.Weight.label))
                    .foregroundStyle(PuffCandy.tangerine.deep)
                Button("重新解析") {
                    model.retryRevision += 1
                }
                .buttonStyle(GrammarActionButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sourceHeader(
                    title: "AI 独立解析",
                    detail: "仅供参考",
                    systemImage: "sparkles",
                    tint: PuffCandy.grape.deep
                )
                Button("开始 AI 解析") {
                    model.retryRevision += 1
                }
                .buttonStyle(GrammarActionButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectAIAnalysis() {
        withAnimation(Puff.Motion.bouncy) {
            model.source = .ai
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
                .font(.puff(.subheadline, Puff.Weight.title))
                .foregroundStyle(tint)
            Spacer(minLength: 8)
            Text(detail)
                .font(.puff(.caption2, Puff.Weight.label))
                .foregroundStyle(Puff.Palette.inkFaint)
        }
    }

    private func localPointCard(_ item: LocalGrammarAnalysisItem, number: Int) -> some View {
        grammarCard(
            number: number,
            title: item.point.title,
            favorite: GrammarFavoriteDescriptor(
                id: item.point.id,
                title: item.point.title,
                explanationZh: item.point.explanationZh
            )
        ) {
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
                    .foregroundStyle(Puff.Palette.inkSoft)
            }
        }
    }

    private func aiPointCard(_ point: AIGrammarAnalysis.Point, number: Int) -> some View {
        grammarCard(
            number: number,
            title: point.title,
            favorite: GrammarFavoriteDescriptor(
                id: aiGrammarPointID(point),
                title: point.title,
                explanationZh: point.explanationZh
            )
        ) {
            quote(
                point.quote,
                contextID: "grammar-\(request.id.uuidString)-ai-\(number)-quote"
            )
            lookupText(
                point.pattern,
                contextID: "grammar-\(request.id.uuidString)-ai-\(number)-pattern"
            )
                .font(.footnote.monospaced())
                .foregroundStyle(PuffCandy.sky.deep)
            Text(point.explanationZh)
                .font(.subheadline)
            Label(point.learnerTipZh, systemImage: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(Puff.Palette.inkSoft)
        }
    }

    private func grammarCard<Content: View>(
        number: Int,
        title: String,
        favorite: GrammarFavoriteDescriptor,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(number)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(PuffCandy.sky.base, in: Circle())
                Text(title)
                    .font(.puff(.headline, Puff.Weight.title))
                    .frame(maxWidth: .infinity, alignment: .leading)
                grammarFavoriteButton(favorite)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .puffCard(radius: Puff.Radius.large)
    }

    private func grammarFavoriteButton(_ favorite: GrammarFavoriteDescriptor) -> some View {
        let isFavorite = favoriteGrammarPointIDs.contains(favorite.id)
        let isUpdating = updatingGrammarPointIDs.contains(favorite.id)
        return Button {
            toggleGrammarFavorite(favorite)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isFavorite ? PuffCandy.sunny.base : Puff.Palette.inkFaint)
        .disabled(isUpdating)
        .accessibilityLabel(isFavorite ? "取消收藏语法点" : "收藏语法点")
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }

    private func quote(_ text: String, contextID: String) -> some View {
        lookupText(text, contextID: contextID)
            .font(.footnote.weight(.medium))
            .foregroundStyle(PuffCandy.sky.deep)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(PuffCandy.sky.wash, in: RoundedRectangle(cornerRadius: 8))
    }

    private func lookupText(_ text: String, contextID: String) -> some View {
        TappableText(
            tokens: TokenCache.tokens(for: text, cacheKey: contextID),
            contextID: contextID,
            selection: wordSelection,
            onSelect: { wordSelection = $0 }
        )
    }

    private func toggleGrammarFavorite(_ favorite: GrammarFavoriteDescriptor) {
        guard !updatingGrammarPointIDs.contains(favorite.id) else { return }
        updatingGrammarPointIDs.insert(favorite.id)
        Haptics.selection()
        Task {
            if let isFavorite = try? await favorites.toggleGrammarPoint(
                id: favorite.id,
                title: favorite.title,
                explanationZh: favorite.explanationZh
            ) {
                if isFavorite {
                    favoriteGrammarPointIDs.insert(favorite.id)
                } else {
                    favoriteGrammarPointIDs.remove(favorite.id)
                }
            }
            updatingGrammarPointIDs.remove(favorite.id)
        }
    }

    private func reloadGrammarFavorites() async {
        let loaded = (try? await favorites.all()) ?? []
        favoriteGrammarPointIDs = Set(
            loaded.compactMap { favorite in
                favorite.kind == .grammarPoint ? favorite.referenceID : nil
            }
        )
    }

    /// AI 语法点没有本地 ID，以内容的稳定 FNV-1a 摘要作为收藏键。
    private func aiGrammarPointID(_ point: AIGrammarAnalysis.Point) -> String {
        if let id = point.canonicalPointID { return id }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(point.title)|\(point.pattern)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "ai-\(String(hash, radix: 16))"
    }


}

enum GrammarAnalysisErrorPresentation {
    static func message(for error: Error) -> String {
        if error is CoachService.TimeoutError {
            return "AI 解析超时，请重新解析"
        }
        if error is URLError {
            return "网络连接异常，请检查网络后重试"
        }
        if let llmError = error as? LLMError {
            switch llmError {
            case .invalidResponse, .emptyResponse:
                return "AI 返回的解析内容不完整，请重新解析"
            case .http(let status, _):
                if status == 401 { return "AI 服务登录状态已失效，请重新登录后重试" }
                if status == 429 { return "AI 请求较多，请稍后再试" }
                return "AI 解析服务暂时不可用，请稍后重试"
            default:
                break
            }
        }
        return "AI 解析暂时失败，请稍后重试"
    }
}

/// 解析页的小操作按钮：浅色糖果胶囊，按下软软缩一下。
private struct GrammarActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.puff(.subheadline, Puff.Weight.emphasis))
            .foregroundStyle(PuffCandy.sky.deep)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(PuffCandy.sky.wash, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(configuration.isPressed ? Puff.Motion.press : Puff.Motion.release, value: configuration.isPressed)
    }
}
