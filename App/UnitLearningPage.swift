import PersistenceKit
import SwiftUI

struct UnitLearningPage: View {
    let character: CharacterDTO
    let environment: AppEnvironment
    @State private var model: UnitLearningModel?
    @State private var selectedAttemptID: UUID?
    @State private var pendingGrade: Int?

    var body: some View {
        Group {
            if let model, let state = model.states[character.id] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        overview(state)
                        levelCard(state)
                        challengeCard(state, model: model)
                        mainlineCard(state)
                        historyCard(state)
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .navigationDestination(item: $selectedAttemptID) { attemptID in
                    UnitChallengeView(character: character, attemptID: attemptID, model: model)
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
        .navigationTitle("与\(character.displayName)学习")
        .navigationBarTitleDisplayMode(.inline)
        .alert("直接更改英语水平？", isPresented: Binding(
            get: { pendingGrade != nil },
            set: { if !$0 { pendingGrade = nil } }
        )) {
            Button("取消", role: .cancel) { pendingGrade = nil }
            Button("确认更改", role: .destructive) {
                guard let grade = pendingGrade, let model else { return }
                pendingGrade = nil
                Task { await model.changeGrade(character: character, to: grade) }
            }
        } message: {
            Text("将所有角色的当前学习水平直接改为\(gradeName(pendingGrade ?? 1))，本级星星进度归零。已完成记录保留；旧年级正在进行的挑战可继续练习，但不能为新年级加分。新聊天和新挑战会使用所选水平。")
        }
        .task(id: character.id) {
            model = environment.unitLearning()
            await model?.refresh(character: character)
        }
    }

    private func overview(_ state: UnitLearningState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("共同学习").font(.largeTitle.bold())
            Text("你和\(character.displayName)的聊天会积累单元挑战进度。每条双方发送的消息只计一次。")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("角色挑战独立 · 英语水平全局共享")
                .font(.caption.weight(.medium)).foregroundStyle(.teal)
        }
    }

    private func levelCard(_ state: UnitLearningState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前水平").font(.caption).foregroundStyle(.secondary)
                    Text(gradeName(state.progress.grade)).font(.title2.bold())
                }
                Spacer()
                Text("\(state.progress.gradeCorrect) / \(state.progress.gradeTarget) 道新答对")
                    .font(.subheadline.monospacedDigit())
            }
            HStack(spacing: 7) {
                ForEach(0..<state.progress.starsPerGrade, id: \.self) { index in
                    Image(systemName: index < state.progress.stars ? "star.fill" : "star")
                        .foregroundStyle(index < state.progress.stars ? .yellow : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("每答对 \(state.progress.correctPerStar) 道新题点亮一颗星；九颗星后进入下一年级。旧题重复答对不加分。")
                .font(.caption).foregroundStyle(.secondary)
            Menu("手动调整学习水平") {
                ForEach(1...12, id: \.self) { grade in
                    Button(gradeName(grade)) { pendingGrade = grade }
                        .disabled(grade == state.progress.grade)
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("unitLearning.level")
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
            ForEach(state.history) { attempt in
                Button { selectedAttemptID = attempt.id } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(attempt.template.title).font(.headline)
                            Text("\(gradeName(attempt.grade)) · 答对 \(attempt.correctCount) / \(attempt.questionCount)")
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

    private func mainlineCard(_ state: UnitLearningState) -> some View {
        let scenes = UnitLearningMainline.scenes(role: UnitLearningModel.roleKey(for: character))
        let unlocked = scenes.filter { $0.requiredCompletedLevels <= state.progress.completedLevels }
        return VStack(alignment: .leading, spacing: 12) {
            Text("学习主线").font(.title3.bold())
            if scenes.isEmpty {
                Text("这位角色的学习主线还在创作中。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if unlocked.isEmpty {
                Text("提升到下一个年级，开启与\(character.displayName)的新章节。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(unlocked) { scene in
                NavigationLink {
                    UnitLearningMainlineView(scene: scene)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scene.title).font(.headline)
                            Text(scene.setup).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func gradeName(_ grade: Int) -> String {
        let years = ["一", "二", "三", "四", "五", "六"]
        guard (1...12).contains(grade) else { return "英语学习" }
        if grade <= 6 { return "小学\(years[grade - 1])年级" }
        if grade <= 9 { return "初中\(years[grade - 7])年级" }
        return "高中\(years[grade - 10])年级"
    }
}

private struct UnitChallengeView: View {
    let character: CharacterDTO
    let attemptID: UUID
    let model: UnitLearningModel
    @Environment(\.dismiss) private var dismiss

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
                    ForEach(attempt.template.scene.indices, id: \.self) { index in
                        let beat = attempt.template.scene[index]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(beat.speaker == "character" ? character.displayName : "剧情")
                                .font(.caption.bold()).foregroundStyle(.teal)
                            Text(beat.english).font(.body)
                            Text(beat.chinese).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    ForEach(attempt.template.questions) { question in
                        UnitQuestionCard(character: character, attempt: attempt,
                                         question: question, model: model)
                    }
                    if attempt.completedAt != nil {
                        Text("本轮已完成 · 答对 \(attempt.correctCount) / \(attempt.questionCount)")
                            .font(.headline)
                        Text("未答对的题可以在这里重答；同一道题只在首次答对时增加一次水平进度。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("返回学习页") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("单元挑战")
        .navigationBarTitleDisplayMode(.inline)
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
                    }
                }
                HStack {
                    Button("清空") { selectedTokens.removeAll() }
                        .buttonStyle(.bordered)
                        .disabled(selectedTokens.isEmpty)
                    Button("提交排序") { submit(selectedTokens.map { question.options[$0] }.joined(separator: " ")) }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedTokens.count != question.options.count)
                }
            } else {
                TextField("输入英文答案", text: $written)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("提交答案") { submit(written) }
                    .buttonStyle(.borderedProminent)
                    .disabled(written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let previous = attempt.answers[question.id], !isCorrect {
                Text("上次回答：\(previous)").font(.caption).foregroundStyle(.secondary)
            }
            if let feedback = model.lastAnswer,
               feedback.attemptID == attempt.id, feedback.questionID == question.id {
                Text(feedback.awarded ? "答对了，获得 1 点水平进度。"
                     : feedback.correct ? "答对了。这是旧年级的记录，当前水平不再重复计分。"
                     : "还没答对，完成本轮后再来试试。")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(feedback.correct ? .green : .orange)
                if let explanation = feedback.explanation { Text(explanation).font(.footnote) }
                if feedback.levelAdvanced { Text("水平进阶！新的挑战将按下一年级出题。") }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func submit(_ answer: String) {
        Task { await model.answer(character: character, attemptID: attempt.id,
                                  questionID: question.id, text: answer) }
    }
}
