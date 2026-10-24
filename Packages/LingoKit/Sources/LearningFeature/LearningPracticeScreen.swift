import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

private enum PracticePaper {
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.10, green: 0.12, blue: 0.11, alpha: 1) : UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1) })
    static let sheet = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.16, blue: 0.15, alpha: 1) : UIColor(red: 1, green: 0.995, blue: 0.98, alpha: 1) })
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.65, green: 0.79, blue: 0.70, alpha: 1) : UIColor(red: 0.25, green: 0.39, blue: 0.32, alpha: 1) })
}

/// The shared task UI used by live practice, including the real testing entry.
@MainActor
struct LearningPracticeScreen: View {
    private let character: CharacterDTO
    @State private var model: LearningPracticeModel
    @State private var panel: Panel = .standard
    @State private var evidenceRequest = 0
    @State private var gapRequest = 0
    @State private var highlightedParagraph: Int?
    @FocusState private var grammarFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var resultSize = 56
    private enum Panel { case collapsed, standard, expanded }

    init(model: LearningPracticeModel, character: CharacterDTO) {
        self.character = character
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
            panel = .standard; highlightedParagraph = nil; grammarFocused = false
        }
        .onChange(of: model.question.id) { _, _ in highlightedParagraph = nil }
    }

    private var cover: some View {
        VStack(spacing: 0) {
            HStack {
                closeButton { model.save(); dismiss() }
                Spacer()
                Text(model.isProduction ? "练习" : "交互预览").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PRACTICE / 练习").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(PracticePaper.accent)
                        Text("给自己一段\n专注的时间。")
                            .font(.system(.largeTitle, design: .serif, weight: .medium)).lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 22)
                    if model.tasks.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                                Button { model.selectTask(index) } label: {
                                    Text(task.label).font(.subheadline.weight(model.taskIndex == index ? .semibold : .regular))
                                        .padding(.horizontal, 17).frame(minHeight: 44)
                                        .background(model.taskIndex == index ? PracticePaper.accent.opacity(0.12) : Color.clear, in: Capsule())
                                        .overlay(Capsule().strokeBorder(model.taskIndex == index ? PracticePaper.accent.opacity(0.3) : Color.primary.opacity(0.1)))
                                }.buttonStyle(.plain)
                                    .accessibilityAddTraits(model.taskIndex == index ? .isSelected : [])
                                    .accessibilityIdentifier("practice.task.\(task.id)")
                            }
                        }
                    }.scrollIndicators(.hidden).contentMargins(.trailing, 2)
                    }
                    taskCard
                    HStack(alignment: .top, spacing: 12) {
                        avatar(size: 42)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(character.displayName).font(.caption.weight(.semibold)).foregroundStyle(PracticePaper.accent)
                            Text("慢慢来，完成一篇后，我们再一起回看。")
                                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                        }
                    }
                    Label("离开也没关系，回来可以接着做。", systemImage: "bookmark")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            VStack(spacing: 12) {
                primary(model.draft.completed ? "查看本次回顾" : model.hasProgress ? "继续练习" : "开始练习", symbol: "arrow.right") { model.start() }
                    .accessibilityIdentifier("practice.start")
                Text(model.isProduction ? "进度自动保存 · 完成整篇后查看讲解" : "本地示例 · 进度单独保存 · 不计入正式成绩").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 14).frame(maxWidth: 640)
        }
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack {
                Label(model.currentAttempt.map { learningLevelName($0.level) + " · 完整语篇" } ?? "高中 · 原创语篇", systemImage: "book.pages")
                Spacer()
                if model.hasProgress { Text(model.draft.completed ? "已完成" : "已答 \(model.totalAnswered) 题") }
            }.font(.caption).foregroundStyle(PracticePaper.accent)
            VStack(alignment: .leading, spacing: 9) {
                Text(model.task.headline).font(.system(.title, design: .serif, weight: .medium))
                Text("\(model.questionCount) 题   ·   约 \(model.task.minutes) 分钟")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Divider().overlay(PracticePaper.accent.opacity(0.06))
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(model.task.sections.enumerated()), id: \.element.id) { index, section in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit()).foregroundStyle(PracticePaper.accent)
                        Text(section.title).font(.system(.body, design: .serif)).lineSpacing(3)
                        Spacer(minLength: 0)
                    }
                }
            }
            Text(model.task.detail).font(.caption).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(PracticePaper.sheet, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.05)))
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            workspaceHeader
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    PracticeArticleReader(model: model, highlightedParagraph: highlightedParagraph,
                                          evidenceRequest: evidenceRequest, gapRequest: gapRequest) { index in
                        model.selectQuestion(index); gapRequest += 1
                        if panel == .collapsed { animate { panel = .standard } }
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
                    Text(model.draft.isReviewing ? "本篇回顾" : model.task.label).font(.subheadline.weight(.semibold))
                    Text("第 \(model.draft.sectionIndex + 1) / \(model.task.sections.count) 篇")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.draft.isReviewing ? "集中讲解" : "自动保存", systemImage: model.draft.isReviewing ? "text.book.closed" : "checkmark.circle")
                    .font(.caption2).foregroundStyle(.secondary)
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
    private func panelHeight(_ available: CGFloat) -> CGFloat {
        if panel == .collapsed { return 78 }
        if panel == .expanded { return max(220, available * 0.74) }
        return min(model.section.kind == .grammar ? 270 : 355, max(220, available * 0.50))
    }
    private var answerPanel: some View {
        VStack(spacing: 0) {
            Button {
                grammarFocused = false
                animate { panel = panel == .collapsed ? .standard : panel == .standard ? .expanded : .collapsed }
            } label: {
                VStack(spacing: 8) {
                    Capsule().fill(Color.secondary.opacity(0.28)).frame(width: 32, height: 4).padding(.top, 9)
                    HStack {
                        Text(model.section.kind == .insertion && !model.draft.isReviewing ? (model.isSevenOfFive ? "七选五 · 整篇作答" : "选句填空 · 整篇作答") : model.section.kind == .reading ? "第 \(model.draft.questionIndex + 1) 题" : "第 \(model.draft.questionIndex + 1) 空")
                            .font(.subheadline.weight(.semibold))
                        Text("\(model.answeredCount) / \(model.sectionQuestionCount) 已答")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: panel == .collapsed ? "chevron.up" : panel == .expanded ? "chevron.down" : "arrow.up.left.and.arrow.down.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal, 24).padding(.bottom, 12)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(panel == .collapsed ? "展开答题面板" : panel == .standard ? "放大答题面板" : "收起答题面板")
                .accessibilityIdentifier("practice.panel")
                .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
                    grammarFocused = false
                    animate { panel = value.translation.height > 0 ? .collapsed : .expanded }
                })
            if panel != .collapsed {
                Divider().opacity(0.5)
                questionNavigation
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(model.section.kind == .insertion && !model.draft.isReviewing ? "共用选项 A–\(model.question.options.last?.id ?? "G")" : model.question.prompt).font(.body.weight(.medium)).lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button { model.toggleFlag() } label: {
                                Image(systemName: model.draft.flagged.contains(model.question.id) ? "bookmark.fill" : "bookmark")
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(PracticePaper.accent)
                                .accessibilityLabel(model.draft.flagged.contains(model.question.id) ? "取消稍后回看" : "标记稍后回看")
                        }
                        if model.draft.isReviewing { explanation }
                        else if !model.isRequired(model.question) {
                            Text("这一空本轮无需补答，保留完整文章供阅读。").font(.subheadline).foregroundStyle(.secondary)
                        }
                        else if model.section.kind == .grammar { grammarInput.disabled(model.isLocked(model.question) || model.isBusy || model.hasUnconfirmedAnswer) }
                        else {
                            if model.section.kind == .insertion {
                                Text("点击文章中的空位或上方空号，再选句子；填完 \(model.section.questions.count) 空后整篇提交。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(model.question.options) { option in choice(option) }
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 16)
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
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(model.section.questions.enumerated()), id: \.element.id) { index, question in
                        Button {
                            model.selectQuestion(index)
                            if model.section.kind == .grammar && !model.draft.isReviewing { grammarFocused = true }
                        } label: {
                            VStack(spacing: 3) {
                                Text(model.section.kind == .insertion && !model.answer(for: question).isEmpty
                                     ? "\(index + 1) \(model.answer(for: question))" : "\(index + 1)")
                                    .font(.caption.weight(.semibold)).monospacedDigit()
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
                }.padding(.horizontal, 20).padding(.vertical, 9)
            }.scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(model.question.id, anchor: .center) }
                .onChange(of: model.question.id) { _, id in proxy.scrollTo(id, anchor: .center) }
        }
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
            }.padding(.horizontal, 14).padding(.vertical, 13).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
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
            Text("按原文括号提示填词；没有提示词时填一个适当的词。")
                .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
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
                animate { panel = .standard }
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
                HStack(spacing: 12) {
                    if model.section.kind != .reading && !model.answer(for: model.question).isEmpty {
                        Button("清空本空") { model.setAnswer("") }.font(.caption).frame(minHeight: 44).disabled(model.isBusy || model.hasUnconfirmedAnswer || model.isLocked(model.question))
                    } else if !model.canReview && !dynamicTypeSize.isAccessibilitySize {
                        Text("本篇完成后集中讲解").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        if model.canReview { grammarFocused = false; Task { await model.submitSection() } }
                        else { nextQuestion() }
                    } label: {
                        Text(model.isBusy ? "正在提交…" : model.canReview ? "完成本篇 · 看讲解" : model.section.kind == .insertion ? "填完本篇后提交" : "下一题 →")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 46)
                            .foregroundStyle(PracticePaper.sheet).background(PracticePaper.accent, in: Capsule())
                    }.buttonStyle(.plain).disabled(model.isBusy || (model.section.kind == .insertion && !model.canReview)).accessibilityIdentifier("practice.next")
                }.padding(.horizontal, 24).padding(.vertical, 10)
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
        VStack(spacing: 0) {
            HStack {
                closeButton { model.goToCover() }
                Spacer()
                Text("本次回顾").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 12) {
                        avatar(size: 46)
                        Text("完成了。一起看看值得回看的地方。")
                            .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                    }.padding(.top, 22)
                    Text("这一段，\n完成了。")
                        .font(.system(.largeTitle, design: .serif, weight: .medium)).lineSpacing(5)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(model.correctCount)").font(.system(size: resultSize, weight: .medium, design: .serif))
                        Text("/ \(model.questionCount) 题").font(.title3).foregroundStyle(.secondary)
                        Spacer()
                        Text("本次答对").font(.subheadline).foregroundStyle(PracticePaper.accent)
                    }
                    if model.needsReviewCount > 0 {
                        Text("另有 \(model.needsReviewCount) 题表达待核对，不直接判错。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Text("值得再看一眼").font(.headline)
                        Spacer()
                        Text("错题与标记").font(.caption).foregroundStyle(.secondary)
                    }
                    let items = reviewItems
                    if items.isEmpty {
                        Label("本次全部答对，可以再读一遍喜欢的段落。", systemImage: "checkmark.circle")
                            .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                        ForEach(Array(model.task.sections.enumerated()), id: \.element.id) { index, section in
                            Button { model.revisit(section: index, question: section.questions.firstIndex(where: model.isRequired) ?? 0) } label: {
                                HStack { Text(section.title); Spacer(); Image(systemName: "arrow.up.right") }
                                    .font(.subheadline).frame(minHeight: 48)
                            }.buttonStyle(.plain)
                        }
                    } else {
                        ForEach(items, id: \.question.id) { item in
                            Button { model.revisit(section: item.section, question: item.index) } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack {
                                        Text("第 \(item.section + 1) 篇 · 第 \(item.index + 1) 题").font(.caption).foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: model.draft.flagged.contains(item.question.id) ? "bookmark.fill" : "arrow.up.right")
                                            .font(.caption).foregroundStyle(PracticePaper.accent)
                                    }
                                    Text(item.question.prompt).font(.subheadline).lineSpacing(4)
                                    Text(resultLabel(item.question)).font(.caption).foregroundStyle(questionColor(item.question))
                                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(PracticePaper.sheet, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 28).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            primary("返回任务", symbol: "arrow.right") { model.goToCover() }
                .padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: 640)
        }
    }
    private var reviewItems: [(section: Int, index: Int, question: LearningPracticeQuestion)] {
        model.task.sections.enumerated().flatMap { si, section in
            section.questions.enumerated().compactMap { qi, question in
                model.isRequired(question) && (model.result(for: question) != .correct || model.draft.flagged.contains(question.id)) ? (si, qi, question) : nil
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
    private func avatar(size: CGFloat) -> some View {
        AvatarBadge(name: character.displayName, size: size, imageName: character.card.avatarAssetName,
                    remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
    }
    private func primary(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: symbol) }
                .font(.body.weight(.semibold)).padding(.horizontal, 22).frame(minHeight: 56)
                .foregroundStyle(PracticePaper.sheet).background(PracticePaper.accent, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(LearningPressStyle())
    }
    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.045), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel("关闭练习预览")
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
                    Text(section.kind == .reading ? "PASSAGE \(String(format: "%02d", model.draft.sectionIndex + 1))" : section.kind == .grammar ? "GRAMMAR IN CONTEXT" : section.kind == .insertion ? "CHOOSE THE SENTENCE" : "COMPLETE THE STORY")
                        .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(PracticePaper.accent)
                    Text(section.title).font(.system(.title, design: .serif, weight: .medium)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(section.instruction).font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                }.padding(.top, 28).padding(.bottom, 5)
                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(attributed(paragraph)).font(.system(size: readingSize, design: .serif)).lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(highlightedParagraph == index ? 12 : 0)
                        .background(highlightedParagraph == index ? PracticePaper.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        .id(index)
                }
                Text("— 全文结束 —").font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
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
    @State private var model: LearningPracticeModel
    public init(character: CharacterDTO) {
        self.character = character
        _model = State(initialValue: LearningPracticeModel(tasks: PracticePreviewFixtures.tasks,
            namespace: ProcessInfo.processInfo.environment["UI_TEST_PRACTICE_NAMESPACE"] ?? "practice.preview.v1"))
    }
    public var body: some View { LearningPracticeScreen(model: model, character: character) }
}
#endif
