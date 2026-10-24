import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// The shared task UI used by live practice, including the real testing entry.
@MainActor
struct LearningPracticeScreen: View {
    private let character: CharacterDTO
    @State private var companion: PracticeCompanionPresentation
    @State private var model: LearningPracticeModel
    @State private var panel: Panel = .expanded
    @State private var evidenceRequest = 0
    @State private var gapRequest = 0
    @State private var highlightedParagraph: Int?
    @FocusState private var grammarFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Panel { case collapsed, expanded }

    init(model: LearningPracticeModel, character: CharacterDTO, companion: PracticeCompanionPresentation? = nil) {
        self.character = character
        _companion = State(initialValue: companion ?? PracticeCompanionPresentation(character: character))
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let error = model.error {
                LearningErrorBanner(message: error) {
                    Task {
                        if model.draft.isReviewing { await model.finishReview() }
                        else { await model.recover(); await model.submitSection() }
                    }
                }.padding(.horizontal, 20)
            }
            switch model.page {
            case .cover: cover
            case .work: workspace
            case .summary: summary
            }
        }
        .background(PracticePaper.canvas.ignoresSafeArea())
        .tint(PracticePaper.accent)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.save() } }
        .onDisappear { model.save() }
        .onChange(of: model.section.id) { _, _ in
            panel = .expanded; highlightedParagraph = nil; grammarFocused = false
        }
        .onChange(of: model.question.id) { _, _ in highlightedParagraph = nil }
    }

    private var cover: some View {
        PracticeCoverPage(character: character, message: companion.opening, kind: model.task.kindTitle,
                          minutes: model.task.minutes,
                          buttonTitle: model.draft.completed ? "查看本次回顾" : model.hasProgress ? "继续作答" : "开始作答",
                          start: { model.start() }, close: { model.save(); dismiss() }) {
            // Multiple tasks only exist in the isolated design fixture.
            if model.tasks.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                            Button { model.selectTask(index) } label: {
                                Text(task.label).font(.subheadline)
                                    .padding(.horizontal, 16).frame(minHeight: 44)
                                    .background(model.taskIndex == index ? PracticePaper.accent.opacity(0.12) : .clear, in: Capsule())
                            }.buttonStyle(.plain).accessibilityIdentifier("practice.task.\(task.id)")
                        }
                    }.padding(.horizontal, 24)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            workspaceHeader
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    PracticeArticleReader(model: model, highlightedParagraph: highlightedParagraph,
                                          evidenceRequest: evidenceRequest, gapRequest: gapRequest) { index in
                        model.selectQuestion(index); gapRequest += 1
                        if panel == .collapsed { animate { panel = .expanded } }
                        grammarFocused = model.section.kind == .grammar && !model.draft.isReviewing
                    }
                    .id(model.section.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    answerPanel.frame(height: panelHeight(geometry.size.height))
                }
            }
        }
    }
    private var workspaceHeader: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                Button {
                    grammarFocused = false; model.goToCover()
                } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("保存并返回任务")
                    .accessibilityIdentifier("practice.back")
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.draft.isReviewing ? "本篇回顾" : sectionKindTitle).font(.subheadline.weight(.semibold))
                    Text("第 \(model.draft.sectionIndex + 1) / \(model.task.sections.count) 篇")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: model.draft.isReviewing ? "text.book.closed" : "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityLabel(model.draft.isReviewing ? "本篇回顾" : "进度自动保存")
            }.padding(.leading, 8).padding(.trailing, 22)
            GeometryReader { geometry in
                Rectangle().fill(PracticePaper.accent.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(PracticePaper.accent)
                            .frame(width: geometry.size.width * Double(model.totalAnswered) / Double(model.questionCount))
                    }
            }.frame(height: 2)
        }.padding(.top, 4)
    }
    private var sectionKindTitle: String {
        switch model.section.kind {
        case .reading: "阅读理解"
        case .cloze: "完形填空"
        case .insertion: model.isSevenOfFive ? "七选五" : "选句填空"
        case .grammar: "语法填空"
        }
    }
    private func panelHeight(_ available: CGFloat) -> CGFloat {
        if panel == .collapsed { return 44 }
        // One expanded height, with room reserved for the passage when a keyboard or small window reduces space.
        return min(320, max(0, available - 140))
    }
    private var answerPanel: some View {
        VStack(spacing: 0) {
            Button {
                grammarFocused = false
                animate { panel = panel == .collapsed ? .expanded : .collapsed }
            } label: {
                Image(systemName: panel == .collapsed ? "chevron.compact.up" : "chevron.compact.down")
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(panel == .collapsed ? "展开答题面板" : "收起答题面板")
                .accessibilityValue("已答 \(model.answeredCount) / \(model.sectionQuestionCount)")
                .accessibilityIdentifier("practice.panel")
            if panel != .collapsed {
                questionNavigation
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.section.kind == .insertion && !model.draft.isReviewing {
                            Text("共用选项 A–\(model.question.options.last?.id ?? "G")").font(.body).foregroundStyle(.secondary)
                        } else if LearningQuestionText.showsPrompt(model.question.prompt, instruction: model.section.instruction, material: model.section.text) {
                            Text(model.question.prompt).font(.body).foregroundStyle(.secondary).lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if model.draft.isReviewing { explanation }
                        else if !model.isRequired(model.question) {
                            Text("这一空本轮无需补答，保留完整文章供阅读。").font(.subheadline).foregroundStyle(.secondary)
                        }
                        else if model.section.kind == .grammar { grammarInput.disabled(model.isLocked(model.question) || model.isBusy || model.hasUnconfirmedAnswer) }
                        else {
                            ForEach(model.question.options) { option in choice(option) }
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 8)
                }.scrollDismissesKeyboard(.interactively)
                    .id("\(model.question.id).\(model.draft.isReviewing)")
                    .accessibilityIdentifier("practice.answers")
                panelFooter
            }
        }
        .background(PracticePaper.sheet, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .strokeBorder(Color.primary.opacity(0.07)).allowsHitTesting(false)
        }
        .clipped()
    }
    private var questionNavigation: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(Array(model.section.questions.enumerated()), id: \.element.id) { index, question in
                            Button {
                                model.selectQuestion(index)
                                if model.section.kind == .grammar && !model.draft.isReviewing { grammarFocused = true }
                            } label: {
                                VStack(spacing: 3) {
                                    Text(model.section.kind == .insertion && !model.answer(for: question).isEmpty
                                         ? "\(index + 1) \(model.answer(for: question))" : "\(index + 1)")
                                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                                    Circle().fill(questionColor(question)).frame(width: 4, height: 4)
                                }.frame(width: 44, height: 44).contentShape(Rectangle())
                                    .background(index == model.draft.questionIndex ? PracticePaper.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 11))
                                    .overlay(alignment: .topTrailing) {
                                        if model.draft.flagged.contains(question.id) {
                                            Image(systemName: "bookmark.fill").font(.system(size: 7)).foregroundStyle(PracticePaper.accent).padding(4)
                                        }
                                    }
                            }.buttonStyle(.plain).id(question.id)
                                .accessibilityLabel("第 \(index + 1) 题，\(model.answer(for: question).isEmpty ? "未答" : "已答")")
                                .accessibilityAddTraits(index == model.draft.questionIndex ? .isSelected : [])
                                .accessibilityIdentifier("practice.question.\(index + 1)")
                        }
                    }
                }.scrollIndicators(.hidden)
                    .onAppear { proxy.scrollTo(model.question.id, anchor: .center) }
                    .onChange(of: model.question.id) { _, id in proxy.scrollTo(id, anchor: .center) }
            }
            if model.section.kind != .reading && !model.draft.isReviewing && !model.answer(for: model.question).isEmpty {
                Button { model.setAnswer("") } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(PracticePaper.accent)
                    .disabled(model.isBusy || model.hasUnconfirmedAnswer || model.isLocked(model.question))
                    .accessibilityLabel("清空本空").accessibilityIdentifier("practice.clear")
            }
            Button { model.toggleFlag() } label: {
                Image(systemName: model.draft.flagged.contains(model.question.id) ? "bookmark.fill" : "bookmark")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(PracticePaper.accent)
                .accessibilityLabel(model.draft.flagged.contains(model.question.id) ? "取消稍后回看" : "标记稍后回看")
        }.padding(.horizontal, 20).padding(.bottom, 4)
    }
    private func questionColor(_ question: LearningPracticeQuestion) -> Color {
        switch model.result(for: question) {
        case .correct: PracticePaper.accent
        case .incorrect: .orange
        case .needsReview: .secondary
        case nil: model.answer(for: question).isEmpty ? Color.secondary.opacity(0.18) : PracticePaper.accent
        }
    }
    private func choice(_ option: LearningPracticeQuestion.Option) -> some View {
        let selected = model.answer(for: model.question) == option.id
        let previous = model.section.kind == .insertion ? model.section.questions.firstIndex(where: { $0.id != model.question.id && model.answer(for: $0) == option.id }) : nil
        // Selecting a radio option is idempotent, including across two questions with the same letter.
        return Button { model.setAnswer(option.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 13) {
                Text(option.id).font(.subheadline.weight(.medium)).foregroundStyle(PracticePaper.accent)
                    .frame(width: 23)
                VStack(alignment: .leading, spacing: 5) {
                    Text(option.text).font(.body).lineSpacing(4).foregroundStyle(.primary)
                    if let previous { Text("已用于第 \(previous + 1) 空 · 点选移到这里").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(PracticePaper.accent) }
            }.padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(selected ? PracticePaper.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? PracticePaper.accent.opacity(0.5) : Color.primary.opacity(0.10)))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .disabled(model.isBusy || model.hasUnconfirmedAnswer || model.isLocked(model.question) || (previous.map { model.isLocked(model.section.questions[$0]) } ?? false))
            .accessibilityIdentifier("practice.option.\(option.id)")
    }
    private var grammarInput: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("Type your answer", text: Binding(get: { model.answer(for: model.question) }, set: { model.setAnswer($0) }))
                .font(.system(.title3, design: .serif))
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                .submitLabel(.next).focused($grammarFocused)
                .padding(16).background(PracticePaper.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PracticePaper.accent.opacity(0.3)))
                .accessibilityLabel("第 \(model.draft.questionIndex + 1) 空的答案")
                .accessibilityIdentifier("practice.grammar.answer")
                .onSubmit { nextQuestion() }
        }
    }
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(resultLabel(model.question), systemImage: resultSymbol(model.question))
                .font(.subheadline.weight(.semibold)).foregroundStyle(questionColor(model.question))
            Text("你的答案  \(model.answerLabel(model.question))").font(.subheadline).foregroundStyle(.secondary)
            if model.result(for: model.question) != .correct {
                Text("参考答案  \(model.referenceLabel(model.question))").font(.subheadline.weight(.medium))
            }
            Text(model.explanation(for: model.question)).font(.subheadline).lineSpacing(5)
            if model.result(for: model.question) == .needsReview {
                Text("此为预览参考答案，其他合理表达留待核对。").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                highlightedParagraph = model.isProduction && model.section.kind == .reading ? nil : model.question.evidenceParagraph
                evidenceRequest += 1
                animate { panel = .expanded }
            } label: {
                Label(model.isProduction ? "回看原文" : "定位原文依据", systemImage: "text.viewfinder").font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("practice.evidence")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var panelFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            if model.draft.isReviewing {
                HStack(spacing: 12) {
                    if model.draft.questionIndex + 1 < model.section.questions.count {
                        Button("下一题讲解") { nextQuestion() }.font(.subheadline).frame(minHeight: 48)
                    }
                    Spacer(minLength: 0)
                    Button(model.returningToSummary ? "返回本次回顾" : model.draft.sectionIndex + 1 < model.task.sections.count ? "继续下一篇 →" : "完成练习 →") {
                        grammarFocused = false; Task { await model.finishReview() }
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 48)
                        .accessibilityIdentifier("practice.continue")
                }.padding(.horizontal, 24)
            } else {
                Button {
                    if model.canReview { grammarFocused = false; Task { await model.submitSection() } }
                    else { nextQuestion() }
                } label: {
                    Text(model.isBusy ? "正在提交…" : model.canReview || model.section.kind == .insertion ? "提交本篇" : "下一题")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(PracticePaper.sheet).background(PracticePaper.accent, in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).disabled(model.isBusy || (model.section.kind == .insertion && !model.canReview))
                    .accessibilityIdentifier("practice.next")
                    .padding(.horizontal, 32).padding(.vertical, 8)
            }
        }
    }
    private func nextQuestion() {
        let index = model.draft.questionIndex
        if let next = model.section.questions.indices.first(where: { $0 > index && model.isRequired(model.section.questions[$0]) }) { model.selectQuestion(next) }
        else if let first = model.section.questions.firstIndex(where: { model.isRequired($0) && model.answer(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            model.selectQuestion(first)
        } else { model.selectQuestion(0) }
    }

    private var summary: some View {
        PracticeSummaryPage(character: character, message: companion.closing,
                            correct: model.correctCount, total: model.questionCount,
                            items: reviewItems.map { item in
                                PracticeReviewItem(id: item.question.id,
                                    location: "第 \(item.section + 1) 篇 · 第 \(item.index + 1) 题",
                                    prompt: item.question.prompt, answer: model.answerLabel(item.question),
                                    reference: model.referenceLabel(item.question),
                                    needsReview: model.result(for: item.question) == .needsReview)
                            }, revisit: { id in
                                if let item = reviewItems.first(where: { $0.question.id == id }) {
                                    model.revisit(section: item.section, question: item.index)
                                }
                            }, finish: { model.save(); dismiss() })
    }
    private var reviewItems: [(section: Int, index: Int, question: LearningPracticeQuestion)] {
        model.task.sections.enumerated().flatMap { si, section in
            section.questions.enumerated().compactMap { qi, question in
                model.isRequired(question) && model.result(for: question) != .correct ? (si, qi, question) : nil
            }
        }
    }
    private func resultLabel(_ question: LearningPracticeQuestion) -> String {
        switch model.result(for: question) {
        case .correct: "本次答对"
        case .incorrect: "这一题，再看一眼"
        case .needsReview: "表达待核对"
        case nil: model.isRequired(question) ? "尚未提交" : "本轮无需补答"
        }
    }
    private func resultSymbol(_ question: LearningPracticeQuestion) -> String {
        switch model.result(for: question) {
        case .correct: "checkmark.circle"
        case .incorrect: "arrow.counterclockwise.circle"
        case .needsReview, nil: "questionmark.circle"
        }
    }
    private func animate(_ changes: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22), changes)
    }
}

private struct PracticeArticleReader: View {
    let model: LearningPracticeModel
    let section: LearningPracticeSection
    let initialOffset: Double
    let highlightedParagraph: Int?
    let evidenceRequest: Int
    let gapRequest: Int
    let selectGap: (Int) -> Void
    @State private var position: ScrollPosition
    @ScaledMetric(relativeTo: .body) private var readingSize = 19

    init(model: LearningPracticeModel, highlightedParagraph: Int?, evidenceRequest: Int, gapRequest: Int, selectGap: @escaping (Int) -> Void) {
        self.model = model; self.section = model.section
        self.initialOffset = model.readingOffset(for: model.section.id)
        self.highlightedParagraph = highlightedParagraph
        self.evidenceRequest = evidenceRequest; self.gapRequest = gapRequest; self.selectGap = selectGap
        _position = State(initialValue: ScrollPosition(y: model.readingOffset(for: model.section.id)))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    if !section.title.isEmpty {
                        Text(section.title).font(.system(.title, design: .serif, weight: .medium)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(section.instruction).font(.body).foregroundStyle(.secondary).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("practice.instruction")
                }.padding(.top, 20).padding(.bottom, 4)
                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(attributed(paragraph)).font(.system(size: readingSize, design: .serif)).lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(highlightedParagraph == index ? 12 : 0)
                        .background(highlightedParagraph == index ? PracticePaper.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        .id(index)
                }
            }.padding(.horizontal, 26).padding(.bottom, 22).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .onAppear { position.scrollTo(y: initialOffset) }
        .onScrollGeometryChange(for: Double.self) { Double(max(0, $0.contentOffset.y + $0.contentInsets.top)) } action: { _, offset in
            model.rememberReadingOffset(offset, for: section.id)
        }
        .onChange(of: model.question.id) { _, _ in
            if section.kind != .reading && model.section.id == section.id {
                position.scrollTo(id: model.question.evidenceParagraph, anchor: .top)
            }
        }
        .onChange(of: gapRequest) { _, _ in
            position.scrollTo(id: model.question.evidenceParagraph, anchor: .top)
        }
        .onChange(of: evidenceRequest) { _, _ in
            if let highlightedParagraph { position.scrollTo(id: highlightedParagraph, anchor: .top) }
            else { position.scrollTo(y: 0) }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "practice-gap", let index = Int(url.host ?? ""), section.questions.indices.contains(index) else { return .discarded }
            selectGap(index); return .handled
        })
        .accessibilityIdentifier("practice.article")
    }
    private func attributed(_ paragraph: String) -> AttributedString {
        guard let regex = try? NSRegularExpression(pattern: "____([0-9]+)____") else { return AttributedString(paragraph) }
        let source = paragraph as NSString
        let matches = regex.matches(in: paragraph, range: NSRange(location: 0, length: source.length))
        var output = AttributedString(); var cursor = 0
        for match in matches {
            output.append(AttributedString(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            guard let number = Int(source.substring(with: match.range(at: 1))), section.questions.indices.contains(number - 1) else { continue }
            let question = section.questions[number - 1]
            let response = model.answer(for: question)
            let content = question.options.first(where: { $0.id == response }).map { section.kind == .insertion ? "\($0.id). \($0.text)" : $0.text } ?? response
            var gap = AttributedString(content.isEmpty ? "  \(number) ____  " : "  \(number) · \(content)  ")
            gap.link = URL(string: "practice-gap://\(number - 1)")
            gap.foregroundColor = PracticePaper.accent
            gap.backgroundColor = PracticePaper.accent.opacity(model.draft.questionIndex == number - 1 ? 0.17 : 0.07)
            gap.underlineStyle = .single
            output.append(gap); cursor = match.range.location + match.range.length
        }
        output.append(AttributedString(source.substring(from: cursor)))
        return output
    }
}

#if DEBUG
/// Isolated design fixture. Real practice and the testing entry use LearningChallengeView instead.
@MainActor
public struct LearningPracticePreview: View {
    private let character: CharacterDTO
    @State private var companion: PracticeCompanionPresentation
    @State private var model: LearningPracticeModel
    public init(character: CharacterDTO) {
        self.character = character
        _companion = State(initialValue: PracticeCompanionPresentation(character: character))
        _model = State(initialValue: LearningPracticeModel(tasks: PracticePreviewFixtures.tasks,
            namespace: ProcessInfo.processInfo.environment["UI_TEST_PRACTICE_NAMESPACE"] ?? "practice.preview.v1"))
    }
    public var body: some View { LearningPracticeScreen(model: model, character: character, companion: companion) }
}
#endif
