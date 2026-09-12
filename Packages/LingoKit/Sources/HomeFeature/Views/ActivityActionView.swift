import CoreKit
import DesignSystem
import DictKit
import DomainKit
import PersistenceKit
import SpeechKit
import SwiftUI

/// A self-contained encounter story with shared dictionary and speech controls.
struct ActivityActionView: View {
    var activity: SceneActivity { model.activity }
    let isVisible: Bool
    let onBack: () -> Void
    let onComplete: ([Int], UUID, CharacterDTO?, [String]) throws -> Void
    let deps: HomeDependencies
    @ObservedObject var model: SocialEncounterModel
    @ObservedObject var journey: ActivityJourneyCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsTranscript = false
    @State private var saved = false
    @State private var saveError: String?
    @State private var wordSelection: TokenSelection?
    private let ink = Color.dsSceneTextPrimary

    init(model: SocialEncounterModel, journey: ActivityJourneyCoordinator, deps: HomeDependencies, isVisible: Bool,
         onBack: @escaping () -> Void,
         onComplete: @escaping ([Int], UUID, CharacterDTO?, [String]) throws -> Void) {
        self.model = model; self.journey = journey; self.deps = deps; self.isVisible = isVisible
        self.onBack = onBack; self.onComplete = onComplete
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isVisible || scenePhase != .active)) { timeline in
            Group {
                if model.started && !model.canReveal(at: timeline.date) {
                    ActivityJourneyTransitionView(deadline: model.revealAt ?? timeline.date, now: timeline.date,
                        cityID: model.region.id, cityName: model.region.nameZh,
                        isVisible: isVisible && scenePhase == .active, error: model.error,
                        onRetry: model.retry)
                } else if !model.started {
                    preparationContent
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
        .wordLookupOverlay(selection: $wordSelection, dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                Task { await deps.speech.speak(SpeechRequest(text: word, purpose: .pronunciation)) }
            }, favoriteActions: WordFavoriteActions(
                contains: { (try? await deps.favorites.isWordFavorited($0)) ?? false },
                toggle: { (try? await deps.favorites.toggleWord($0, translationZh: $1)) ?? false }),
            exampleTranslationActions: deps.exampleTranslationActions,
            allowsSystemTranslationFallback: deps.tutorial == nil)
    }

    private var navigationHeader: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.accessibilityLabel("返回场景").accessibilityIdentifier("activities.action.back")
            Spacer()
            Text(model.region.nameZh + " · " + activity.scene.title)
                .font(.caption).foregroundStyle(ink.opacity(0.7))
        }
    }

    private var preparationContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    navigationHeader
                    Spacer(minLength: 28)
                    VStack(spacing: 22) {
                        Text(activity.title).font(.largeTitle.weight(.semibold))
                        Text(activity.introduction).font(.body).lineSpacing(6)
                            .foregroundStyle(ink.opacity(0.75))
                        primary("出发", id: "activities.action.start") { journey.start() }
                            .padding(.top, 10)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 38)
                .frame(minHeight: geometry.size.height)
            }.scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.dsBackground.ignoresSafeArea())
        .accessibilityIdentifier("activities.confirmation")
    }

    private var resultContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                navigationHeader
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
                lookupText(character.card.occupation, key: "occupation").font(.subheadline)
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
                Text(activity.title).font(.largeTitle.weight(.semibold))
                Text(activity.introduction).lineSpacing(5)
                primary("出发，给相遇一点时间", id: "activities.action.start") { journey.start() }
            } else {
                if model.summary {
                    summary
                } else {
                    if let part = model.chapters.indices.contains(model.step) ? model.chapters[model.step] : nil {
                        Text(model.chapters.first?.title ?? part.title).font(.system(.title, design: .serif))
                        if let beat = model.currentBeat {
                            HStack {
                                Text(beat.speaker == "npc" ? (model.character?.displayName ?? "对方") : "此刻")
                                    .font(.caption.weight(.semibold)).foregroundStyle(ink.opacity(0.6))
                                Spacer()
                                Button { model.speak() } label: {
                                    Image(systemName: "speaker.wave.2").frame(width: 44, height: 44)
                                }.accessibilityLabel("播放当前剧情").accessibilityIdentifier("activities.story.play")
                                Button { showsTranscript.toggle() } label: {
                                    Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44)
                                }.accessibilityLabel("回看已读剧情").accessibilityIdentifier("activities.story.history")
                                    .accessibilityValue(showsTranscript ? "展开" : "收起")
                            }
                            lookupText(beat.english, key: "beat-\(model.step)-\(model.beatIndex)")
                                .font(.system(.title3, design: .serif)).lineSpacing(6)
                            Text(beat.chinese).font(.subheadline).lineSpacing(4).foregroundStyle(ink.opacity(0.75))
                        }
                        if showsTranscript {
                            VStack(alignment: .leading, spacing: 18) {
                            ForEach(0...model.step, id: \.self) { stage in
                                ForEach(Array(model.chapters[stage].beats.enumerated()), id: \.offset) { index, beat in
                                    if stage < model.step || index <= model.beatIndex {
                                        VStack(alignment: .leading, spacing: 5) {
                                            lookupText(beat.english, key: "history-\(stage)-\(index)")
                                            Text(beat.chinese).font(.caption).foregroundStyle(.secondary)
                                        }.padding(.vertical, 6)
                                    }
                                }
                            }
                            }
                            .padding(16).background(ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        }
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
            if !model.selections.isEmpty {
                DisclosureGroup("回顾你的选择") {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(model.selections.enumerated()), id: \.offset) { index, selected in
                            let choice = model.chapters[index].choices[selected]
                            VStack(alignment: .leading, spacing: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("你的选择").font(.caption).foregroundStyle(.secondary)
                                    lookupText(choice.english, key: "summary-choice-\(index)").font(.headline)
                                    Text(choice.chinese).font(.subheadline).foregroundStyle(.secondary)
                                }
                                if model.chapters.indices.contains(index + 1) {
                                    ForEach(Array(model.chapters[index + 1].beats.enumerated()), id: \.offset) { beatIndex, beat in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(beat.speaker == "npc" ? (model.character?.displayName ?? "对方") : "随后")
                                                .font(.caption).foregroundStyle(.secondary)
                                            lookupText(beat.english, key: "summary-beat-\(index)-\(beatIndex)").font(.body)
                                            Text(beat.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.7)).lineSpacing(4)
                                        }
                                    }
                                }
                            }
                            if index + 1 < model.selections.count { Divider() }
                        }
                    }.padding(.vertical, 16)
                }
            }
            if model.canConnect, let character = model.character, !character.isFriend {
                primary(model.contactBusy ? "正在添加…" : "加为好友", id: "activities.encounter.addFriend") { model.addFriend() }
                    .disabled(model.contactBusy)
            }
            if let message = model.contactMessage {
                Text(message).font(.caption).accessibilityIdentifier("activities.encounter.contactStatus")
            }
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            primary("告别，回到活动", id: "activities.action.finish") {
                do {
                    if !saved {
                        try onComplete(model.selections, model.runID, model.character, model.responses)
                        saved = true
                    }
                    onBack()
                } catch { saveError = "记录未保存，已有数据未改动。请重试。" }
            }
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
