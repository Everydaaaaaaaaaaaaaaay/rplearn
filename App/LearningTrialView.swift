#if DEBUG
import BackendKit
import CoreKit
import DesignSystem
import DomainKit
import LearningFeature
import PersistenceKit
import SpeechKit
import SwiftUI

/// 真实账号入口：不引用 DebugLearningPreviewService，也不提供本地判分。
struct LearningTrialView: View {
    let environment: AppEnvironment
    @State private var model: LearningTrialModel
    @State private var characters: [CharacterDTO] = []
    @State private var selectedCharacterID: UUID?
    @State private var rosterError: String?
    @State private var originalFamily = ""

    init(environment: AppEnvironment) {
        self.environment = environment
        let backend = environment.backendClient
        let commands = environment.userState
        _model = State(initialValue: LearningTrialModel(service: backend, changeLevel: { level in
            let result = try await commands.updateProfile { profile in
                profile.difficultyLevel = level
                profile.proficiencySource = .selfReported
            }
            guard result.difficultyLevel == level else { throw BackendClientError.invalidResponse }
        }, fillCycle: { characterID, cycleID, requestID in
            try await backend.debugFillLearning(characterID, cycleID: cycleID, requestID: requestID)
        }))
    }

    var body: some View {
        Form {
            Section {
                Label("使用当前账号的正式题库", systemImage: "checkmark.shield")
                Text("与旅伴学习使用同一套题面、播放器、答题、解析和补答界面。切换档位会同步到账号，答题与奖励照常记录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("旅伴") {
                if characters.isEmpty {
                    Text(rosterError ?? "请先在通讯录添加一位旅伴，再回来开始练习。")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("和谁一起练习", selection: $selectedCharacterID) {
                        ForEach(characters) { character in
                            Text(character.displayName).tag(Optional(character.id))
                        }
                    }.accessibilityIdentifier("learning.trial.character")
                }
            }
            Section("选择档位") {
                ForEach(LearningTrialModel.levels, id: \.rawValue) { level in
                    Button { model.selectedLevel = level } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.displayName).foregroundStyle(.primary)
                                if let state = model.journey?.levels.first(where: { $0.level == level.rawValue }) {
                                    Text(state.publishedUnitCount.map { $0 == 0 ? "暂无已发布练习" : "已发布 \($0) 套练习" } ?? "可抽取数量以开始时为准")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else { Text("等待服务器确认").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if model.selectedLevel == level { Image(systemName: "checkmark").foregroundStyle(Color.dsSkyDeep) }
                        }
                    }
                    .accessibilityIdentifier("learning.trial.level.\(level.rawValue)")
                    .accessibilityAddTraits(model.selectedLevel == level ? .isSelected : [])
                }
            }
            Section("原创完整题组") {
                if let originals = model.originals {
                    Text("已发布 \(originals.units.count) 组；保留全文、全部子题与配套输入。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("题型", selection: $originalFamily) {
                        Text("全部题型").tag("")
                        ForEach(Array(Set(originals.units.map(\.family))).sorted(), id: \.self) { family in
                            Text(originals.units.first(where: { $0.family == family })?.label ?? family).tag(family)
                        }
                    }.accessibilityIdentifier("learning.trial.family")
                    Picker("选择题组", selection: $model.selectedOriginalID) {
                        if originalFamily.isEmpty { Text("自动抽取").tag(Optional<String>.none) }
                        ForEach(originals.units.filter { originalFamily.isEmpty || $0.family == originalFamily }) { unit in
                            Text("\(unit.label) · \(unit.title)（\(unit.questions)题）").tag(Optional(unit.id))
                        }
                    }.accessibilityIdentifier("learning.trial.original")
                } else if let error = model.originalsError {
                    Text(error).foregroundStyle(.red)
                    Button("重新读取原创题组") { Task { await model.loadOriginals() } }
                } else { ProgressView("读取正式原创题库…") }
            }
            if let attempt = model.activeAttempt {
                Section("进行中的挑战") {
                    Text(attempt.unit.title)
                    Text("\(DifficultyLevel(rawValue: attempt.level)?.displayName ?? attempt.level) · \(attempt.unit.questions.count) 题")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("继续这次挑战") { Task { await model.resume() } }
                        .accessibilityIdentifier("learning.trial.resume")
                }
            }
        }
        .disabled(model.isBusy)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let message = model.error ?? rosterError {
                    Text(message).font(.footnote).foregroundStyle(.red)
                    Button("重新加载") { Task { await load() } }
                        .disabled(model.isBusy)
                }
                if let notice = model.notice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                }
                if let current = model.journey?.currentLevel {
                    Text("账号当前档位：\(DifficultyLevel(rawValue: current)?.displayName ?? current)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    if let selectedCharacterID { Task { await model.start(characterID: selectedCharacterID) } }
                } label: {
                    HStack {
                        if model.isBusy { ProgressView().tint(.white) }
                        Text("开始\(model.selectedLevel.displayName)练习").fontWeight(.semibold)
                    }.frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.journey == nil || selectedCharacterID == nil)
                .accessibilityIdentifier("learning.trial.start")
                Text("直接开始通用英语，略过聊天进度等待。已有挑战保留原档位。")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding().background(.regularMaterial)
        }
        .navigationTitle("学习实测")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("刷新题库", systemImage: "arrow.clockwise") { Task { await load(); await model.loadOriginals() } }
                .disabled(model.isBusy)
        }
        .task { await load() }
        .task(id: model.selectedLevel) { originalFamily = ""; await model.loadOriginals() }
        .onChange(of: originalFamily) { _, family in
            model.selectedOriginalID = family.isEmpty ? nil : model.originals?.units.first(where: { $0.family == family })?.id
        }
        .onChange(of: selectedCharacterID) { previous, current in
            // 首次选旅伴由 load() 顺序完成；避免 id 变化取消正在读取的初始请求。
            guard previous != nil else { return }
            Task { await model.load(characterID: current) }
        }
        .fullScreenCover(item: $model.presentedAttempt, onDismiss: {
            Task { await model.load(characterID: selectedCharacterID) }
        }) { attempt in
            if let character = characters.first(where: { $0.id == attempt.characterId }) {
                LearningChallengeView(attempt: attempt, character: character, service: environment.backendClient,
                    audioSession: environment.audioSession, speech: environment.speech,
                    beforePlayback: { await environment.speech.stopSpeaking() },
                    afterFinish: { await environment.workspace?.learningChat.challengeCompleted(characterID: character.id) })
            }
        }
    }

    private func load() async {
        do {
            characters = try await environment.rosterStore.friends().sorted { $0.displayName < $1.displayName }
            rosterError = nil
            if !characters.contains(where: { $0.id == selectedCharacterID }) { selectedCharacterID = characters.first?.id }
            await model.load(characterID: selectedCharacterID)
        } catch { rosterError = error.localizedDescription }
    }
}
#endif
