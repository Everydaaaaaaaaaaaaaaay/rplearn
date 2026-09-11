import CoreKit
import DesignSystem
import DictKit
import DomainKit
import PersistenceKit
import SpeechKit
import SwiftUI

/// A real private conversation over the shared scene, not a disconnected quiz.
struct ActivityActionView: View {
    var activity: SceneActivity { model.activity }
    let isVisible: Bool
    let onBack: () -> Void
    let onChat: (CharacterDTO) -> Void
    let onComplete: ([Int], UUID, CharacterDTO?, [String]) throws -> Void
    let deps: HomeDependencies
    @ObservedObject var model: SocialEncounterModel
    @ObservedObject var journey: ActivityJourneyCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoVoice = false
    @State private var showsTranscript = false
    @State private var saved = false
    @State private var saveError: String?
    @State private var wordSelection: TokenSelection?
    private let ink = Color.dsSceneTextPrimary

    init(model: SocialEncounterModel, journey: ActivityJourneyCoordinator, deps: HomeDependencies, isVisible: Bool,
         onBack: @escaping () -> Void, onChat: @escaping (CharacterDTO) -> Void,
         onComplete: @escaping ([Int], UUID, CharacterDTO?, [String]) throws -> Void) {
        self.model = model; self.journey = journey; self.deps = deps; self.isVisible = isVisible
        self.onBack = onBack; self.onChat = onChat; self.onComplete = onComplete
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isVisible || scenePhase != .active)) { timeline in
            Group {
                if model.started && !model.canReveal(at: timeline.date) {
                    ActivityJourneyTransitionView(deadline: model.revealAt ?? timeline.date, now: timeline.date,
                        cityID: model.region.id, cityName: model.region.nameZh,
                        isVisible: isVisible && scenePhase == .active, error: model.error,
                        onRetry: model.retry)
                } else {
                    resultContent
                }
            }
        }
        .foregroundStyle(ink)
        .allowsHitTesting(isVisible)
        .onDisappear { model.stopSpeech() }
        .onChange(of: isVisible) { _, visible in if !visible { model.stopSpeech() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stopSpeech() } }
        .onChange(of: wordSelection != nil) { _, showing in if showing { model.stopSpeech() } }
        .onChange(of: model.reply?.english) { _, _ in
            if autoVoice && model.canReveal && isVisible && scenePhase == .active && wordSelection == nil { model.speak() }
        }
        .wordLookupOverlay(selection: $wordSelection, dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                Task { await deps.speech.speak(SpeechRequest(text: word, purpose: .pronunciation)) }
            }, favoriteActions: WordFavoriteActions(
                contains: { (try? await deps.favorites.isWordFavorited($0)) ?? false },
                toggle: { (try? await deps.favorites.toggleWord($0, translationZh: $1)) ?? false }),
            exampleTranslationActions: deps.exampleTranslationActions)
    }

    private var resultContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }.accessibilityLabel("返回场景").accessibilityIdentifier("activities.action.back")
                    Spacer()
                    Text(model.region.nameZh + " · " + activity.scene.title)
                        .font(.caption).tracking(1.5)
                }
                if model.isSolitude {
                    solitudeContent
                } else {
                    if model.started, let character = model.character { identity(character) }
                    panel
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 38)
        }
        .tint(ink)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.dsBackground.ignoresSafeArea())
        .accessibilityIdentifier(model.started ? "activities.result" : "activities.confirmation")
    }

    private func identity(_ character: CharacterDTO) -> some View {
        HStack(spacing: 14) {
            AvatarBadge(name: character.card.name, size: 52, imageName: character.card.avatarAssetName,
                remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
            VStack(alignment: .leading, spacing: 5) {
                Text(character.displayName).font(.title2.weight(.semibold))
                Text(character.card.occupation).font(.subheadline).foregroundStyle(ink.opacity(0.65))
            }
            Spacer(minLength: 0)
        }.accessibilityIdentifier("activities.encounter.identity")
    }

    private var solitudeContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("与城市独处的一刻").font(.caption).tracking(2).foregroundStyle(ink.opacity(0.6))
            Image(systemName: "leaf").font(.system(size: 52, weight: .ultraLight)).padding(.vertical, 16)
            Text(activity.solitude.title).font(.system(.largeTitle, design: .serif))
            Rectangle().fill(ink.opacity(0.15)).frame(height: 0.5)
            Text(activity.solitude.story).font(.title3).lineSpacing(9)
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            primary("记下这一刻，回到城市", id: "activities.solitude.finish") {
                do {
                    try onComplete([], model.runID, nil, [])
                    onBack()
                } catch { saveError = "这段足迹暂时没能保存，请再试一次。" }
            }.padding(.top, 22)
        }.accessibilityElement(children: .contain)
        .accessibilityIdentifier("activities.solitude")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.started {
                Text("一次相遇，未必从自我介绍开始。").font(.caption).foregroundStyle(ink.opacity(0.65))
                Text(activity.title).font(.largeTitle.weight(.semibold))
                Text(activity.introduction).lineSpacing(5)
                Text("一章小故事 · 两次行动选择 · 结尾自由加好友").font(.caption).foregroundStyle(ink.opacity(0.65))
                primary("出发，给相遇一点时间", id: "activities.action.start") { journey.start() }
            } else {
                if model.summary {
                    summary
                } else {
                    if let part = model.chapters.indices.contains(model.step) ? model.chapters[model.step] : nil {
                        Text(model.chapters.first?.title ?? part.title).font(.system(.title, design: .serif))
                        Text("第 \(model.step + 1) / \(model.chapterCount) 幕 · \(model.beatIndex + 1) / \(part.beats.count)")
                            .font(.caption).foregroundStyle(ink.opacity(0.65))
                        if let beat = model.currentBeat {
                            Text(beat.speaker == "npc" ? (model.character?.displayName ?? "对方") : "此刻")
                                .font(.caption.weight(.semibold)).foregroundStyle(ink.opacity(0.6))
                            lookupText(beat.english, key: "beat-\(model.step)-\(model.beatIndex)")
                                .font(.system(.title3, design: .serif)).lineSpacing(6)
                            Text(beat.chinese).font(.subheadline).lineSpacing(4).foregroundStyle(ink.opacity(0.75))
                            if beat.speaker == "npc" {
                                HStack {
                                    Button { model.speak() } label: { Label("播放台词", systemImage: "speaker.wave.2") }
                                    Spacer()
                                    Button { model.stopSpeech() } label: { Label("停止", systemImage: "stop.circle") }
                                }.frame(minHeight: 44)
                            }
                        }
                        Toggle("自动播放台词", isOn: $autoVoice).font(.subheadline)
                            .onChange(of: autoVoice) { _, enabled in if enabled { model.speak() } else { model.stopSpeech() } }
                        DisclosureGroup("回看已读内容", isExpanded: $showsTranscript) {
                            ForEach(0...model.step, id: \.self) { stage in
                                ForEach(Array(model.chapters[stage].beats.enumerated()), id: \.offset) { index, beat in
                                    if stage < model.step || index < model.beatIndex {
                                        VStack(alignment: .leading, spacing: 5) {
                                            lookupText(beat.english, key: "history-\(stage)-\(index)")
                                            Text(beat.chinese).font(.caption).foregroundStyle(.secondary)
                                        }.padding(.vertical, 6)
                                    }
                                }
                            }
                        }.font(.subheadline)
                        if !model.busy, model.error == nil {
                            if model.atChoice { choices }
                            else {
                                primary(model.atEnding ? "为这次相遇收尾" : "继续故事",
                                        id: "activities.action.next") { model.advance() }
                            }
                        }
                    }
                }
                if model.busy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(model.character == nil ? "看看此刻会遇见谁…" : "等对方回应…").font(.subheadline)
                    }.frame(minHeight: 44).accessibilityIdentifier("activities.encounter.loading")
                }
                if let error = model.error {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                    Button("重试，不更换人物") { model.retry() }
                        .accessibilityIdentifier("activities.encounter.retry")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lookupText(_ text: String, key: String) -> some View {
        TappableText(tokens: TokenCache.tokens(for: text, cacheKey: "chapter-\(model.runID)-\(key)"),
            contextID: "chapter-\(model.runID)-\(key)", textColor: ink, selection: wordSelection,
            onSelect: { wordSelection = $0 }).fixedSize(horizontal: false, vertical: true)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("你想怎么做？").font(.headline)
            ForEach(Array(model.chapters[model.step].choices.enumerated()), id: \.offset) { index, choice in
                VStack(alignment: .leading, spacing: 8) {
                    lookupText(choice.english, key: "choice-\(model.step)-\(index)")
                    Text(choice.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.7))
                    Button("选择这项行动") { model.choose(index) }
                        .frame(minHeight: 44).disabled(model.selected != nil)
                        .accessibilityIdentifier("activities.choice.\(index)")
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.alreadyKnown ? "把这次短短的照面，也留在旅途中。" : activity.closing).font(.system(.title3, design: .serif)).lineSpacing(3)
            if !model.selections.isEmpty {
            DisclosureGroup("回顾你的选择") {
            ForEach(Array(model.selections.enumerated()), id: \.offset) { index, selected in
                let choice = activity.steps[index].choices[selected]
                VStack(alignment: .leading, spacing: 5) {
                    Text(activity.steps[index].question).font(.caption).foregroundStyle(.secondary)
                    lookupText(choice.english, key: "summary-\(index)").font(.subheadline.weight(.medium))
                    Text(model.responses[index]).font(.subheadline).foregroundStyle(ink.opacity(0.75))
                }
            }
            }
            }
            Divider()
            if model.canConnect, let character = model.character {
                Text(character.isFriend ? "你们已经是好友，可以接着聊。" : "要不要把这位旅途中的新朋友加入联系人？由你决定。")
                    .font(.subheadline)
                if !character.isFriend {
                    primary(model.contactBusy ? "正在添加…" : "加为好友", id: "activities.encounter.addFriend") { model.addFriend() }
                        .disabled(model.contactBusy)
                }
                Button("继续聊天") { onChat(character) }
                    .frame(minHeight: 44).accessibilityIdentifier("activities.encounter.chat")
            } else {
                Text("这次交流先停在这里。没有成为好友，也不代表一次相遇没有意义。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let message = model.contactMessage {
                Text(message).font(.caption).accessibilityIdentifier("activities.encounter.contactStatus")
            }
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            primary(saved ? "回到场景" : "就此告别，记下这次相遇", id: "activities.action.finish") {
                do {
                    if !saved {
                        try onComplete(model.selections, model.runID, model.character, model.responses)
                        saved = true
                    }
                    onBack()
                } catch { saveError = "记录未保存，已有数据未改动。请重试。" }
            }
            Text("已读台词与选择会保留；不会自动添加好友。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }
                .font(.headline).padding(18).frame(maxWidth: .infinity)
                .foregroundStyle(Color.white)
                .background(Color.dsTravelNavy, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(DSSceneEntranceButtonStyle()).accessibilityIdentifier(id)
    }
}
