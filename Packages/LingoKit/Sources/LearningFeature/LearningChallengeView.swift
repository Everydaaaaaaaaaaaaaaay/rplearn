import BackendKit
import DesignSystem
import PersistenceKit
import SwiftUI

public struct LearningChallengeView: View {
    @State private var model: LearningChallengeModel
    private let character: CharacterDTO
    @Environment(\.dismiss) private var dismiss
    @State private var showsExit = false
    @State private var showsHint = false
    @State private var showsTranslation = false
    @FocusState private var inputFocused: Bool
    public init(attempt: LearningAttempt, character: CharacterDTO, service: any LearningServing, afterFinish: @escaping @Sendable () async -> Void = {}) {
        _model = State(initialValue: LearningChallengeModel(attempt: attempt, service: service, afterFinish: afterFinish)); self.character = character
    }
    private var theme: LearningTheme { LearningTheme(role: model.attempt.unit.roleKey) }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch model.stage {
                case .cover: cover
                case .story(let index): story(model.attempt.unit.beats[index])
                case .question: if let question = model.question { questionBody(question) }
                case .summary: summary
                }
                if let error = model.error {
                    LearningErrorBanner(message: error) { Task { await model.recover() } }
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { topBar.background(.regularMaterial) }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .background(Color.dsBackground).tint(theme.tint)
        .interactiveDismissDisabled()
        .confirmationDialog("离开本次挑战？", isPresented: $showsExit, titleVisibility: .visible) {
            Button("保存进度，稍后继续") { dismiss() }
            if model.attempt.firstCompletedAt == nil && !model.hasUnconfirmedAnswer {
                Button("结束首轮，剩余题目稍后补答") {
                    Task { await model.finish(skipRemaining: true) }
                }
            }
            Button("继续挑战", role: .cancel) {}
        } message: {
            Text("已提交的答案会保留。结束首轮会重置该角色的挑战进度条，未答对的题仍可从记录补答。")
        }
        .onChange(of: model.stage) { _, _ in showsHint = false; showsTranslation = false; inputFocused = false }
        .onChange(of: model.feedback?.outcome) { _, outcome in
            if outcome == .correct { Haptics.notify(.success) }
        }
        .accessibilityIdentifier("learning.challenge")
    }
    private var topBar: some View {
        HStack(spacing: 18) {
            Button { inputFocused = false; showsExit = true } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
            }.accessibilityLabel("退出挑战").disabled(model.isBusy)
            ProgressView(value: Double(model.attempt.round.answers.count), total: Double(max(1, model.attempt.round.questionIds.count)))
                .tint(theme.tint).accessibilityLabel("本轮题目进度")
            Text("\(model.attempt.round.answers.count) / \(model.attempt.round.questionIds.count)")
                .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }
    private var cover: some View {
        VStack(alignment: .leading, spacing: 25) {
            ZStack {
                RoundedRectangle(cornerRadius: 30).fill(theme.tint.opacity(0.09))
                Image(systemName: theme.symbol).font(.system(size: 110, weight: .ultraLight)).foregroundStyle(theme.tint.opacity(0.17)).offset(x: 85, y: -25)
                VStack(spacing: 15) {
                    AvatarBadge(name: character.displayName, size: 96, imageName: character.card.avatarAssetName,
                                remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                    Text(character.displayName).font(.headline).foregroundStyle(theme.tint)
                }.padding(36)
            }.frame(height: 230).clipped().accessibilityHidden(true)
            Label("\(learningLevelName(model.attempt.level)) · \(model.attempt.unit.estimatedMinutes) 分钟", systemImage: "book.closed")
                .font(.caption.weight(.medium)).foregroundStyle(theme.tint)
            Text(model.attempt.unit.title).font(.system(.largeTitle, design: .serif).bold())
            Text(model.attempt.unit.summary).font(.title3).foregroundStyle(.secondary)
            Text(model.attempt.unit.scene).font(.subheadline).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            Text("剧情带你进入情景。每一道题都有完整题意，不需要记住剧情细节。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func story(_ beat: LearningBeat) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            Label(model.attempt.unit.title, systemImage: theme.symbol).font(.caption).foregroundStyle(theme.tint)
            Spacer(minLength: 24)
            AvatarBadge(name: character.displayName, size: 86, imageName: character.card.avatarAssetName,
                        remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                .accessibilityHidden(true)
            Text(beat.speaker).font(.subheadline.bold()).foregroundStyle(theme.tint)
            Text(beat.text).font(.system(.title2, design: .serif)).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
            Button(showsTranslation ? "收起中文" : "查看中文") { showsTranslation.toggle() }.font(.subheadline).padding(.vertical, 8)
            if showsTranslation { Text(beat.translation).font(.body).foregroundStyle(.secondary).lineSpacing(5) }
            Spacer(minLength: 24)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func questionBody(_ question: LearningQuestion) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label(model.attempt.round.ordinal > 0 ? "补答 · 剩余题目" : "轮到你了", systemImage: "pencil.tip").font(.caption.bold()).foregroundStyle(theme.tint)
                Spacer()
                Text(learningLevelName(model.attempt.level)).font(.caption).foregroundStyle(.secondary)
            }
            Text(question.instruction).font(.title2.bold())
            Text(question.prompt).font(.system(.title3, design: .rounded)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            if question.audio != nil {
                Label("听力音频暂不可用，可先跳过，稍后从记录补答。", systemImage: "speaker.slash")
                    .font(.subheadline).foregroundStyle(.secondary).padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            }
            answerControls(question)
                .disabled(model.isBusy || model.feedback != nil || model.hasUnconfirmedAnswer)
            if let feedback = model.feedback {
                feedbackCard(feedback, question: question)
            } else {
                Button(showsHint ? "收起提示" : "需要一点提示？") { showsHint.toggle() }
                    .font(.subheadline).padding(.vertical, 8).disabled(model.hasUnconfirmedAnswer)
                if showsHint { Text(question.hint).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }
    @ViewBuilder
    private func answerControls(_ question: LearningQuestion) -> some View {
        switch question.type {
        case .choice, .listeningChoice:
            VStack(spacing: 12) {
                ForEach(question.options ?? []) { option in
                    Button { model.choice = option.id } label: {
                        HStack(spacing: 14) {
                            Image(systemName: model.choice == option.id ? "checkmark.circle.fill" : "circle").font(.title3)
                            Text(option.text).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }.padding(18).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .foregroundStyle(model.choice == option.id ? theme.tint : Color.primary)
                            .background(model.choice == option.id ? theme.tint.opacity(0.09) : Color.dsSurface, in: RoundedRectangle(cornerRadius: 18))
                            .overlay { RoundedRectangle(cornerRadius: 18).stroke(model.choice == option.id ? theme.tint : Color.primary.opacity(0.08), lineWidth: model.choice == option.id ? 2 : 1) }
                    }.buttonStyle(LearningPressStyle()).accessibilityAddTraits(model.choice == option.id ? [.isSelected] : [])
                }
            }
        case .arrange:
            VStack(alignment: .leading, spacing: 18) {
                LearningFlowLayout(spacing: 9) {
                    if model.tokens.isEmpty { Text("点选词块，组成句子").foregroundStyle(.secondary).padding(10) }
                    ForEach(Array(model.tokens.enumerated()), id: \.element) { index, id in
                        tokenButton(question.tokens?.first { $0.id == id }?.text ?? "", selected: true) { model.tokens.remove(at: index) }
                            .accessibilityLabel("第 \(index + 1) 个词，\(question.tokens?.first { $0.id == id }?.text ?? "")")
                            .accessibilityHint("轻点移回词库")
                            .accessibilityAction(named: "向前移动") { if index > 0 { model.tokens.swapAt(index, index - 1) } }
                            .accessibilityAction(named: "向后移动") { if index + 1 < model.tokens.count { model.tokens.swapAt(index, index + 1) } }
                    }
                }.frame(maxWidth: .infinity, minHeight: 80, alignment: .leading).padding(14)
                    .background(theme.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                LearningFlowLayout(spacing: 9) {
                    ForEach(question.tokens ?? []) { token in
                        tokenButton(token.text, selected: false) { model.tokens.append(token.id) }
                            .disabled(model.tokens.contains(token.id)).opacity(model.tokens.contains(token.id) ? 0.25 : 1)
                    }
                }
            }
        case .completion, .dictation:
            TextField("在这里输入英文", text: $model.text, axis: .vertical)
                .font(.title3).lineLimit(2...5).textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.asciiCapable).focused($inputFocused).padding(20)
                .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.tint.opacity(0.35)) }
                .accessibilityLabel("填写答案")
        case .matching:
            VStack(alignment: .leading, spacing: 14) {
                Text("先点左侧，再点对应的右侧；再次选择可调整配对。").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) {
                        ForEach(Array((question.left ?? []).enumerated()), id: \.element.id) { index, option in
                            matchingButton(option, number: index + 1, selected: model.selectedLeft == option.id,
                                           paired: model.pairs.contains { $0.left == option.id }) { model.selectedLeft = option.id }
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(spacing: 12) {
                        ForEach(question.right ?? []) { option in
                            let pair = model.pairs.first { $0.right == option.id }
                            let number = pair.flatMap { p in question.left?.firstIndex { $0.id == p.left } }.map { $0 + 1 }
                            matchingButton(option, number: number, selected: false, paired: pair != nil) { model.selectPair(right: option.id) }
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
    private func tokenButton(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).font(.body.weight(.medium)).padding(.horizontal, 15).padding(.vertical, 13)
                .foregroundStyle(selected ? theme.tint : Color.primary)
                .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? theme.tint.opacity(0.5) : Color.primary.opacity(0.12)) }
        }.buttonStyle(LearningPressStyle())
    }
    private func matchingButton(_ option: LearningOption, number: Int?, selected: Bool, paired: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text(number.map { "\($0)" } ?? "—").font(.caption.monospacedDigit().bold()).foregroundStyle(theme.tint)
                Text(option.text).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
            }.padding(15).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background(paired ? theme.tint.opacity(0.09) : Color.dsSurface, in: RoundedRectangle(cornerRadius: 15))
                .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(selected ? theme.tint : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1) }
        }.buttonStyle(LearningPressStyle()).foregroundStyle(.primary)
            .accessibilityValue(paired ? "已配对 \(number ?? 0)" : selected ? "已选中" : "未配对")
    }
    private func feedbackCard(_ grade: LearningGrade, question: LearningQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(grade.outcome == .correct ? (model.awardedPoints > 0 ? "答对了 · +\(model.awardedPoints) 点" : "答对了") : grade.outcome == .skipped ? "先留到下次" : "再认识一下这个表达",
                  systemImage: grade.outcome == .correct ? "checkmark.circle.fill" : "lightbulb")
                .font(.headline).foregroundStyle(grade.outcome == .correct ? theme.tint : Color.primary)
            if grade.outcome != .correct { Text(solutionText(grade.solution, question: question)).font(.body.bold()) }
            Text(grade.explanation).font(.subheadline).lineSpacing(4)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: model.attempt.remainingCount == 0 ? "checkmark.seal" : "book.closed")
                .font(.system(size: 56, weight: .light)).foregroundStyle(theme.tint).padding(.top, 28).accessibilityHidden(true)
            Text(model.attempt.firstCompletedAt == nil ? "把这段收进行囊" : "每一点，都有收获").font(.system(.largeTitle, design: .serif).bold())
            Text(model.attempt.unit.title).font(.title3).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.attempt.correctQuestionIds.count)").font(.system(size: 56, weight: .semibold, design: .rounded))
                Text("/ \(model.attempt.unit.questions.count) 题已掌握").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 13) {
                Text("本轮答对 \(model.roundPoints) 题").font(.headline)
                Text("进度归入：\(learningLevelName(model.attempt.level))").font(.subheadline)
                Text(model.attempt.remainingCount > 0 ? "还有 \(model.attempt.remainingCount) 道题可以补答，获得尚未拿到的进度。" : "这份单元的进度已经全部获得。继续聊天，开启下一段不同的挑战。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.attempt.firstCompletedAt == nil { Text("确认完成后，角色挑战条归零，重新从聊天积累。").font(.caption).foregroundStyle(.secondary) }
            }.modifier(LearningPaper())
            if model.attempt.firstCompletedAt != nil && model.attempt.remainingCount > 0 {
                Button("补答剩余题目") { Task { await model.retry() } }.font(.headline).padding(.vertical, 12).disabled(model.isBusy)
            }
        }
    }
    private var bottomBar: some View {
        VStack(spacing: 10) {
            switch model.stage {
            case .cover:
                primary("进入情景") { model.advance() }
            case .story:
                primary("继续") { model.advance() }
                Button("直接开始题目") { model.skipStory() }.font(.subheadline).padding(8)
            case .question:
                if model.feedback != nil { primary("继续") { model.advance() } }
                else if model.hasUnconfirmedAnswer { primary("重新确认提交") { Task { await model.submit() } } }
                else {
                    primary("检查", disabled: model.answer == nil || model.question?.audio != nil) { inputFocused = false; Task { await model.submit() } }
                    Button("暂时跳过，留待补答") { inputFocused = false; Task { await model.submit(skip: true) } }
                        .font(.subheadline).padding(8).disabled(model.isBusy)
                }
            case .summary:
                if model.attempt.firstCompletedAt == nil { primary("完成本轮挑战") { Task { await model.finish() } } }
                else { primary("回到学习页") { dismiss() } }
            }
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12).frame(maxWidth: 680).frame(maxWidth: .infinity)
            .background(.regularMaterial)
    }
    private func primary(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        LearningPrimaryButton(title: title, tint: theme.tint, busy: model.isBusy, disabled: disabled, action: action)
    }
    private func solutionText(_ answer: LearningAnswer, question: LearningQuestion) -> String {
        switch answer.kind {
        case .choice: return question.options?.first { $0.id == answer.optionId }?.text ?? ""
        case .arrange: return (answer.tokenIds ?? []).compactMap { id in question.tokens?.first { $0.id == id }?.text }.joined(separator: " ")
        case .text: return answer.text ?? ""
        case .matching: return (answer.pairs ?? []).map { pair in
            "\(question.left?.first { $0.id == pair.left }?.text ?? "") ↔ \(question.right?.first { $0.id == pair.right }?.text ?? "")"
        }.joined(separator: "\n")
        case .skip: return ""
        }
    }
}

/// 词块按阅读顺序换行，每块保留独立身份，重复词也能操作。
struct LearningFlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 320, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(width: bounds.width, subviews: subviews).positions
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: min(view.sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var positions: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: min(view.sizeThatFits(.unspecified).width, width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}
