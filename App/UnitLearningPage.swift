import PersistenceKit
import SpeechKit
import SwiftUI

struct UnitLearningPage: View {
    let character: CharacterDTO
    let environment: AppEnvironment
    @State private var model: UnitLearningModel?
    @State private var selectedAttemptID: UUID?

    var body: some View {
        Group {
            if let model, let state = model.states[character.id] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        overview()
                        challengeCard(state, model: model)
                        historyCard(state)
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .navigationDestination(item: $selectedAttemptID) { attemptID in
                    UnitChallengeView(character: character, attemptID: attemptID,
                                      model: model, speech: environment.speech)
                }
                .refreshable { await model.refresh(character: character) }
            } else if let model, let error = model.errors[character.id] {
                ContentUnavailableView {
                    Label("学习记录暂不可用", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await model.refresh(character: character) } }
                }
            } else if model == nil {
                ContentUnavailableView("登录后开启学习页", systemImage: "person.crop.circle",
                                       description: Text("单元挑战和水平进度按账号保存。"))
            } else {
                ProgressView("正在读取学习记录")
            }
        }
        .task(id: character.id) {
            model = environment.unitLearning()
            if model?.states[character.id] == nil,
               model?.busyCharacters.contains(character.id) == false {
                await model?.refresh(character: character)
            }
        }
        .onChange(of: model?.currentGrade) { _, _ in
            guard let model, model.states[character.id] == nil else { return }
            Task { await model.refresh(character: character) }
        }
    }

    private func overview() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("共同学习").font(.largeTitle.bold())
            Text("你和\(character.displayName)的聊天会积累单元挑战进度。每条双方发送的消息只计一次。")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("角色挑战独立 · 英语水平全局共享")
                .font(.caption.weight(.medium)).foregroundStyle(.teal)
        }
    }

    private func challengeCard(_ state: UnitLearningState, model: UnitLearningModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("单元挑战").font(.title3.bold())
                Spacer()
                Text("\(state.progress.chatCharacters) / \(state.progress.challengeLength)")
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: Double(state.progress.chatCharacters), total: Double(state.progress.challengeLength))
                .tint(.teal)
                .accessibilityIdentifier("unitLearning.chatProgress")
            if model.pendingMessageCount(for: character.id) > 0 {
                Text("聊天进度正在同步，数字会自动更新。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let active = state.active {
                Text("正在进行：\(active.template.title)")
                    .font(.subheadline)
                Button("继续挑战") { selectedAttemptID = active.id }
                    .buttonStyle(.borderedProminent)
            } else if state.progress.ready {
                Text("进度已满，可以开启一段新剧情和练习。")
                    .font(.subheadline)
                Button("开启新单元挑战") {
                    Task {
                        await model.start(character: character)
                        if let id = model.states[character.id]?.active?.id { selectedAttemptID = id }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.busyCharacters.contains(character.id))
                .accessibilityIdentifier("unitLearning.start")
            } else {
                Text("继续聊天，进度满后解锁下一个单元。完成当前挑战后计数会重新开始。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = model.errors[character.id] {
                Text(error).font(.footnote).foregroundStyle(.orange)
                Button("重试同步") { Task { await model.refresh(character: character) } }
                    .font(.footnote)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func historyCard(_ state: UnitLearningState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("单元记录").font(.title3.bold())
            if state.history.isEmpty {
                Text("完成的挑战会保存在这里，未答对的题可以回来重答。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 12) {
                ForEach(state.history) { attempt in
                    Button { selectedAttemptID = attempt.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(attempt.template.title).font(.headline)
                                Text("\(UnitLearningGrade.name(attempt.grade)) · 答对 \(attempt.correctCount) / \(attempt.questionCount)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct UnitChallengeView: View {
    private enum Stage: Hashable {
        case scene(Int)
        case question(Int)
        case summary
    }

    let character: CharacterDTO
    let attemptID: UUID
    let model: UnitLearningModel
    let speech: AdaptiveSpeechService
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .scene(0)
    @State private var hasInitializedStage = false

    private var attempt: UnitLearningAttempt? {
        let state = model.states[character.id]
        if state?.active?.id == attemptID { return state?.active }
        return state?.history.first { $0.id == attemptID }
    }

    var body: some View {
        ScrollView {
            if let attempt {
                VStack(alignment: .leading, spacing: 18) {
                    Text(attempt.template.title).font(.largeTitle.bold())
                    Text(attempt.template.objective).foregroundStyle(.secondary)
                    stageProgress(attempt)
                    switch stage {
                    case .scene(let index):
                        if attempt.template.scene.indices.contains(index) {
                            sceneCard(attempt, index: index)
                        }
                    case .question(let index):
                        if attempt.template.questions.indices.contains(index) {
                            let question = attempt.template.questions[index]
                            UnitQuestionCard(character: character, attempt: attempt,
                                             question: question, model: model)
                            if attempt.answers[question.id] != nil {
                                Button(attempt.completedAt != nil ? "返回结果" :
                                       index == attempt.template.questions.count - 1 ? "查看结果" : "下一题") {
                                    advanceQuestion(attempt, after: index)
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("unitLearning.next")
                            }
                        }
                    case .summary:
                        summaryCard(attempt)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.22), value: stage)
            }
        }
        .navigationTitle("单元挑战")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasInitializedStage, let attempt else { return }
            hasInitializedStage = true
            if attempt.completedAt != nil {
                stage = .summary
            } else if attempt.answers.isEmpty == false,
                      let first = attempt.template.questions.firstIndex(where: {
                          attempt.answers[$0.id] == nil
                      }) {
                stage = .question(first)
            }
        }
    }

    @ViewBuilder
    private func stageProgress(_ attempt: UnitLearningAttempt) -> some View {
        let sceneCount = attempt.template.scene.count
        let questionCount = attempt.template.questions.count
        let current: Int = switch stage {
        case .scene(let index): index + 1
        case .question(let index): sceneCount + index + 1
        case .summary: sceneCount + questionCount
        }
        let label: String = switch stage {
        case .scene(let index): "剧情 \(index + 1) / \(sceneCount)"
        case .question(let index): "练习 \(index + 1) / \(questionCount)"
        case .summary: "本轮结果"
        }
        HStack {
            Text(label)
            .font(.caption.weight(.semibold))
            Spacer()
            Text("\(attempt.correctCount) / \(questionCount) 题答对")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        ProgressView(value: Double(current), total: Double(max(1, sceneCount + questionCount)))
            .tint(.teal)
            .accessibilityIdentifier("unitLearning.lessonProgress")
    }

    private func sceneCard(_ attempt: UnitLearningAttempt, index: Int) -> some View {
        let beat = attempt.template.scene[index]
        return VStack(alignment: .leading, spacing: 14) {
            Text(beat.speaker == "character" ? character.displayName : "剧情")
                .font(.caption.bold()).foregroundStyle(.teal)
            Text(beat.english).font(.title3)
            Button {
                let request: SpeechRequest
                if beat.speaker == "character" {
                    request = SpeechRequest(
                        text: beat.english,
                        language: AccentMapper.language(forNationality: character.card.nationality),
                        purpose: .characterDialogue,
                        voiceHint: SpeechVoiceHint(
                            stableID: character.id.uuidString.lowercased(),
                            gender: character.card.gender.rawValue,
                            nationality: character.card.nationality,
                            supertonicVoice: character.card.resolvedReadingVoice
                        ))
                } else {
                    request = SpeechRequest(text: beat.english, voiceHint: StoryVoiceCasting.narrator)
                }
                Task { await speech.speak(request) }
            } label: {
                Label("听这一段", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("unitLearning.playScene")
            if attempt.completedAt != nil {
                Text(beat.chinese).font(.footnote).foregroundStyle(.secondary)
            }
            Button(index == attempt.template.scene.count - 1
                   ? (attempt.completedAt == nil ? "开始练习" : "查看结果")
                   : "下一段剧情") {
                withAnimation {
                    if index + 1 < attempt.template.scene.count {
                        stage = .scene(index + 1)
                    } else if attempt.completedAt != nil {
                        stage = .summary
                    } else if let first = attempt.template.questions.firstIndex(where: {
                        attempt.answers[$0.id] == nil
                    }) {
                        stage = .question(first)
                    } else {
                        stage = .summary
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func summaryCard(_ attempt: UnitLearningAttempt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本轮已完成").font(.title2.bold())
            Text("答对 \(attempt.correctCount) / \(attempt.questionCount) 题")
                .font(.headline).foregroundStyle(.teal)
            Text("错题可以逐题回练；同一道题只有首次答对会增加水平进度。")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("重看剧情") { withAnimation { stage = .scene(0) } }
                .buttonStyle(.bordered)
            ForEach(attempt.template.questions.indices, id: \.self) { index in
                let question = attempt.template.questions[index]
                let correct = attempt.correctQuestionIds.contains(question.id)
                VStack(alignment: .leading, spacing: 6) {
                    Label("第 \(index + 1) 题 · \(correct ? "已答对" : "待回练")",
                          systemImage: correct ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                        .foregroundStyle(correct ? .green : .orange)
                    Text(question.prompt).font(.subheadline)
                    if let answer = question.answer {
                        Text("参考答案：\(answer)").font(.footnote)
                    }
                    if let explanation = question.explanation {
                        Text(explanation).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !correct {
                        Button("重答第 \(index + 1) 题") { withAnimation { stage = .question(index) } }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            Button("返回学习页") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    private func advanceQuestion(_ attempt: UnitLearningAttempt, after index: Int) {
        withAnimation {
            if attempt.completedAt != nil {
                stage = .summary
            } else if index + 1 < attempt.template.questions.count {
                stage = .question(index + 1)
            } else {
                stage = .summary
            }
        }
    }
}

private struct UnitQuestionCard: View {
    let character: CharacterDTO
    let attempt: UnitLearningAttempt
    let question: UnitLearningQuestion
    let model: UnitLearningModel
    @State private var selectedTokens: [Int] = []
    @State private var written = ""

    private var isCorrect: Bool { attempt.correctQuestionIds.contains(question.id) }
    private var hasAnswered: Bool { attempt.answers[question.id] != nil }
    private var isSubmitting: Bool { model.busyCharacters.contains(character.id) }
    private var canAnswer: Bool { !isCorrect && (!hasAnswered || attempt.completedAt != nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(question.prompt).font(.headline)
                Spacer()
                if isCorrect { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if !canAnswer {
                Text(isCorrect ? "已答对，进度已领取" : "本轮已作答。完成单元后可重答。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if question.kind == "choice" {
                ForEach(question.options, id: \.self) { option in
                    Button(option) { submit(option) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(isSubmitting)
                }
            } else if question.kind == "order" {
                Text(selectedTokens.map { question.options[$0] }.joined(separator: " "))
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78))], spacing: 8) {
                    ForEach(question.options.indices, id: \.self) { index in
                        Button(question.options[index]) {
                            if let selected = selectedTokens.firstIndex(of: index) { selectedTokens.remove(at: selected) }
                            else { selectedTokens.append(index) }
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedTokens.contains(index) ? .teal : .gray)
                        .disabled(isSubmitting)
                    }
                }
                HStack {
                    Button("清空") { selectedTokens.removeAll() }
                        .buttonStyle(.bordered)
                        .disabled(selectedTokens.isEmpty || isSubmitting)
                    Button("提交排序") { submit(selectedTokens.map { question.options[$0] }.joined(separator: " ")) }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedTokens.count != question.options.count || isSubmitting)
                }
            } else {
                TextField("输入英文答案", text: $written)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isSubmitting)
                Button("提交答案") { submit(written) }
                    .buttonStyle(.borderedProminent)
                    .disabled(written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
            if isSubmitting { ProgressView("正在判分") }
            if let previous = attempt.answers[question.id], !isCorrect {
                Text("上次回答：\(previous)").font(.caption).foregroundStyle(.secondary)
            }
            if let feedback = model.lastAnswer,
               feedback.attemptID == attempt.id, feedback.questionID == question.id {
                Text(feedback.rewardPending ? "答对了，完成本轮后统一结算。"
                     : feedback.correct ? "答对了。"
                     : "还没答对，完成本轮后可以回练。")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(feedback.correct ? .green : .orange)
                if feedback.awardedPoints > 0 {
                    Text("本次结算 +\(feedback.awardedPoints) 点水平进度。")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
                } else if feedback.correct && !feedback.rewardPending {
                    Text("当前水平未增加进度。").font(.footnote).foregroundStyle(.secondary)
                }
                if let explanation = feedback.explanation { Text(explanation).font(.footnote) }
                if feedback.levelAdvanced { Text("水平进阶！新的挑战将按下一年级出题。") }
            }
            if let error = model.errors[character.id] {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func submit(_ answer: String) {
        guard !isSubmitting else { return }
        Task { await model.answer(character: character, attemptID: attempt.id,
                                  questionID: question.id, text: answer) }
    }
}
