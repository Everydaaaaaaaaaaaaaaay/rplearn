#if DEBUG
import AVFoundation
import DomainKit
import PersistenceKit
import SpeechKit
import SwiftUI

struct ConversationLearningDashboard: View {
    let character: CharacterDTO
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var model: ConversationLearningSystem?
    @State private var bank: [LearningListeningItem] = []
    @State private var onlyThisCharacter = false
    @State private var selectedSession: UUID?
    @State private var deleting: UUID?
    var body: some View {
        Group {
            if let model, model.ready { content(model) }
            else if let error = model?.error { ContentUnavailableView("记录暂不可用", systemImage: "externaldrive.badge.exclamationmark", description: Text(error)) }
            else { ContentUnavailableView("需要登录", systemImage: "person.crop.circle", description: Text("登录后在正常聊天中记录成长；这里不会使用固定回复模拟真人。")) }
        }
        .navigationTitle("共同篇章")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model = environment.learningSystem()
            await model?.load()
            if let url = Bundle.main.url(forResource: "listening-v1", withExtension: "json") {
                do { bank = try JSONDecoder().decode([LearningListeningItem].self, from: Data(contentsOf: url)) }
                catch { model?.error = "听力材料未能读取。" }
            }
        }
        .sheet(item: Binding(get: { selectedSession.map(SessionID.init) }, set: { selectedSession = $0?.id })) { selection in
            if let model { LearningListeningView(model: model, sessionID: selection.id, environment: environment) }
        }
        .confirmationDialog("删除这条表达原文？相关能力证据也会撤回，已获得的经验保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除原文", role: .destructive) { if let deleting { model?.delete(deleting) }; deleting = nil }
        }
    }
    private func progressSummary(_ model: ConversationLearningSystem, skill: LearningSystemPolicy.Skill, band: Int) -> String {
        let status = model.state.ledger.status(skill: skill, band: band, now: .now)
        if status == .confirmed { return "已满足本档的跨情境确认条件。" }
        let samples = Array(model.state.ledger.independentEvidence(skill: skill, band: band, now: .now).filter { !$0.confirmation }.suffix(6))
        let successes = samples.filter(\.successful)
        let span = samples.first.flatMap { first in samples.last.map { Int($0.date.timeIntervalSince(first.date) / 86_400) } } ?? 0
        if status == .ready {
            if let date = model.state.ledger.nextConfirmationDate(skill: skill, band: band, now: .now), date > .now {
                return "基础证据已够，下次确认：\(date.formatted(date: .abbreviated, time: .shortened))"
            }
            return "基础证据已够，下一步是不同情境的独立确认。"
        }
        return "独立证据 \(samples.count)/6 · 成功 \(min(5, successes.count))/5 · 主题 \(min(3, Set(successes.map(\.topic)).count))/3 · 跨度 \(min(7, span))/7天"
    }
    private struct SessionID: Identifiable { let id: UUID }
    private func content(_ model: ConversationLearningSystem) -> some View {
        Form {
            Section {
                if case .signedIn = environment.authSession.phase { } else {
                    Text("界面预览：真实模型回顾需要登录，未启用固定回复。") .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("记录聊天中的学习", isOn: Binding(get: { model.state.enabled }, set: { model.setEnabled($0); model.resume(environment: environment) }))
                    .accessibilityIdentifier("learningSystem.enabled")
                Text("只记录开启后新发出的内容。每日至多6批回顾、12次请求，会使用现有模型额度。关闭后停止新回顾。")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("全账号旅程 Lv.\(model.state.ledger.level)", value: "\(model.state.ledger.xp) XP")
                Text("参与经验不代表英语等级。口语和发音不作评价。") .font(.caption).foregroundStyle(.secondary)
            }
            Section("文字沟通 · 全账号") {
                ForEach(LearningSystemPolicy.Skill.allCases, id: \.self) { skill in
                    DisclosureGroup(skill.title) {
                        ForEach(1...3, id: \.self) { band in
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent("第\(band)档", value: model.state.ledger.status(skill: skill, band: band, now: .now).rawValue)
                                    .font(.subheadline)
                                Text(progressSummary(model, skill: skill, band: band)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                NavigationLink("判断依据与间隔") { LearningRulesView() }
            }
            Section("下一次尝试 · 自愿") {
                if let evidence = model.state.ledger.nextReview(now: .now) {
                    Text("换个情境练习：\(evidence.skill.title)")
                    Text("继续在原聊天中表达，不必背原句。") .font(.caption)
                    Button("换个情境，再试一次") {
                        model.startChallenge(skill: evidence.skill, band: evidence.band, characterID: character.id)

                    }.disabled(model.state.challenge != nil)
                    Button("今天先不练") { model.state.ledger.deferredUntil = Date.now.addingTimeInterval(86_400); model.persist() }
                } else { Text("没有到期任务，照常聊天就好。") .foregroundStyle(.secondary) }
                if let challenge = model.state.challenge {
                    Text(challenge.task.instruction).font(.subheadline)
                    Text("返回原来的聊天继续即可。") .font(.caption).foregroundStyle(.secondary)
                    Button("结束这次尝试") { model.endChallenge() }
                } else {
                    Button("来个小练习") { model.startRecommendedChallenge(characterID: character.id) }
                        .disabled(!model.state.enabled)
                    Text("自动选择适合当前证据的目标，不需要设置参数。") .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("听力 · 无字幕选择题") {
                Text("每组6题，每题最多听2遍，3选1。整组交卷后看原文与解释。") .font(.caption)
                ForEach(1...3, id: \.self) { band in
                    let confirmed = LearningListeningSession.confirmed(band: band, sessions: model.state.listening, now: .now)
                    Button {
                        if let ongoing = model.state.listening.last(where: { $0.band == band && $0.finishedAt == nil && !$0.abandoned }) { selectedSession = ongoing.id }
                        else { model.startListening(band: band, bank: bank); selectedSession = model.state.listening.last(where: { $0.band == band && $0.finishedAt == nil && !$0.abandoned })?.id }
                    } label: { LabeledContent("听力\(band)", value: confirmed ? "已确认" : "开始 / 继续") }
                    .disabled(bank.isEmpty).accessibilityIdentifier("learningListening.start.\(band)")
                }
                ForEach(model.state.listening.filter { $0.finishedAt != nil }.reversed()) { session in
                    Button("听力\(session.band) · \(session.score)/6 · 查看原文") { selectedSession = session.id }
                }
            }
            Section("我的表达") {
                Toggle("只看与\(character.displayName)的篇章", isOn: $onlyThisCharacter)
                ForEach(model.state.ledger.evidence.filter { !$0.deleted && (!onlyThisCharacter || $0.characterID == character.id) }.reversed()) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(item.skill.title) · 第\(item.band)档").font(.headline)
                        Text(item.quote).textSelection(.enabled)
                        Text(item.explanation).font(.subheadline)
                        Text("\(item.scores.reduce(0,+))/8 · \(item.independent ? "独立表达证据" : "借助帮助或来源不明")").font(.caption).foregroundStyle(.secondary)
                        Button("删除原文", role: .destructive) { deleting = item.id }
                    }
                }
                if model.state.ledger.evidence.filter({ !$0.deleted }).isEmpty { Text("新的表达会在聊天后自动出现在这里。") .foregroundStyle(.secondary) }
            }
            if model.error != nil || model.state.pending.contains(where: { $0.failure != nil }) { Section { Text(model.error ?? "部分表达尚未完成回顾，已保留；其他聊天会正常记录。").foregroundStyle(.secondary); Button("重试待处理回顾") { Task { await model.review(environment: environment, force: true) } }.disabled(model.reviewing) } }
            if model.reviewing { Section { ProgressView("正在回顾，不影响聊天") } }
            else if model.state.pending.contains(where: { !$0.turns.isEmpty }) {
                Section { Text("还有表达等待回顾。达到每日上限时会保留到之后处理，不影响聊天。") .font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct LearningRulesView: View {
    var body: some View {
        List {
            Section("文字沟通") {
                Text("任务完成、可理解性、衔接、语言控制：每项0–2分。总分至少6分、任务完成2分、其他项至少1分，才计一次成功。")
                Text("待确认：最近6条独立证据至少5条成功，跨3个日期、3个主题，跨度至少7天。")
                Text("确认：再完成2个不同情境的新任务，间隔至少48小时；从首次证据起至少14天。")
                Text("查词、翻译、来源不明或语音转写可以记录参与，不用于确认独立文字能力。")
            }
            Section("复用间隔") { Text("成功后48小时 → 再次成功后7天 → 后续21天。可延后24小时，不累积任务。") }
            Section("听力") { Text("两组不重题，相隔7–30天，每组至少5/6，各分项合计至少3/4。仅表示本产品题目表现，不是CEFR或考试成绩。") }
            Section("证据有效期") { Text("最近90天用于当前能力判断。长期没有新证据显示需重新确认；历史参与经验保留。") }
        }.navigationTitle("判断依据")
    }
}

/// Options remain readable while interaction is locked until audio completes.
private struct LearningListeningOptionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary.opacity(0.25)))
    }
}

private struct LearningListeningView: View {
    @Bindable var model: ConversationLearningSystem
    let sessionID: UUID
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var playbackID: UUID?
    @State private var playingItem: String?
    @State private var audioTask: Task<Void, Never>?
    @State private var audioError: String?
    private var session: LearningListeningSession? { model.state.listening.first { $0.id == sessionID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let session, let item = session.current {
                        Text("第\(session.answers.count + 1)/6题").font(.subheadline).foregroundStyle(.secondary)
                        Text(item.question).font(.title3.bold())
                        Button {
                            play(item)
                        } label: {
                            Label(playbackID == nil ? "播放音频 · 已听\(session.plays[item.id, default: 0])/2遍" : "正在播放", systemImage: "speaker.wave.2.fill")
                                .frame(maxWidth: .infinity).padding()
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("learningListening.play")
                            .disabled(playbackID != nil || session.plays[item.id, default: 0] >= 2)
                        ForEach(item.options.indices, id: \.self) { index in
                            Button { model.answer(sessionID: sessionID, choice: index) } label: {
                                Text(item.options[index]).frame(maxWidth: .infinity, alignment: .leading).padding()
                            }.buttonStyle(LearningListeningOptionStyle()).accessibilityIdentifier("learningListening.option.\(index)")
                                .accessibilityHint(session.plays[item.id, default: 0] == 0 ? "完整听完音频后可选择" : "选择此答案")
                                .disabled(playbackID != nil || session.plays[item.id, default: 0] == 0)
                        }
                        Text("完整听完至少一遍后可作答。交卷前不显示台词与答案。") .font(.caption).foregroundStyle(.secondary)
                    } else if let session {
                        Text("本组 \(session.score)/6").font(.largeTitle.bold()).accessibilityIdentifier("learningListening.result")
                        Text(session.passed ? "本次表现达标；还需另一组新题和间隔证据。" : "先看看没听清的部分，之后可尝试新的题组。")
                        ForEach(session.items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.question).font(.headline)
                                Text("你的选择：\(session.answers[item.id].map { item.options[$0] } ?? "未答")")
                                Text("答案：\(item.options[item.answer])")
                                Text(item.script).textSelection(.enabled)
                                Text(item.explanation).font(.subheadline).foregroundStyle(.secondary)
                                Button("再听原文", systemImage: "speaker.wave.2") { play(item) }.disabled(playbackID != nil)
                            }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    if let audioError { Text(audioError).foregroundStyle(.secondary) }
                }.padding()
            }
            .navigationTitle("听力尝试")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("稍后继续") { stop(); dismiss() } } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .speechPlaybackDidFinish)) { note in
            guard let id = note.object as? UUID, id == playbackID, let itemID = playingItem else { return }
            model.completedPlayback(sessionID: sessionID, itemID: itemID)
            playbackID = nil; playingItem = nil; audioError = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            if let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable { stop() }
        }
        .onChange(of: phase) { _, value in if value != .active { stop() } }
        .onDisappear { stop() }
    }
    private func play(_ item: LearningListeningItem) {
        let id = UUID(); playbackID = id; playingItem = item.id; audioError = nil
        audioTask = Task {
            await environment.speech.speakAndWait(SpeechRequest(text: item.script, language: "en-GB", engine: .supertonic3, allowsSystemFallback: false, playbackID: id))
            try? await Task.sleep(for: .milliseconds(200))
            if playbackID == id { playbackID = nil; playingItem = nil; audioError = "Supertonic-3 音频未完整播放，请稍后重试。本次不计次数，也不会切换为 Apple 语音。" }
        }
    }
    private func stop() {
        playbackID = nil; playingItem = nil; audioTask?.cancel()
        Task { await environment.speech.stopSpeaking() }
    }
}
struct LearningChatAccessory: View {
    let characterID: UUID
    let environment: AppEnvironment
    var body: some View {
        if let model = environment.learningSystemInstance,
           let challenge = model.state.challenge, challenge.characterID == characterID {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.confirmation ? "独立尝试 · 可随时结束" : "自选小练习").font(.caption.bold())
                    Text(challenge.task.instruction).font(.subheadline)
                    Text("直接在下面聊天；使用帮助也可以，会记作辅助练习。").font(.caption).foregroundStyle(.secondary)
                }
                Button("结束", systemImage: "xmark") { model.endChallenge() }.labelStyle(.iconOnly)
            }.padding(12).background(.thinMaterial)
        }
    }
}
#endif
