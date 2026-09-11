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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var saved = false
    @State private var saveError: String?
    @State private var wordSelection: TokenSelection?
    @State private var contentHeight: CGFloat = 0
    private let ink = Color(red: 0.10, green: 0.18, blue: 0.17)

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
            if model.canReveal && isVisible && scenePhase == .active { model.speak() }
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
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(red: 0.965, green: 0.958, blue: 0.936).ignoresSafeArea())
        .accessibilityIdentifier(model.started ? "activities.result" : "activities.confirmation")
    }

    private func identity(_ character: CharacterDTO) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.alreadyKnown ? "在人群中，再次遇见" : "旅途中，一个新的名字")
                .font(.caption).tracking(2).foregroundStyle(ink.opacity(0.6))
            HStack(alignment: .center, spacing: 22) {
                AvatarBadge(name: character.card.name, size: 100,
                    imageName: character.card.avatarAssetName,
                    remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                    usesPendingPlaceholder: true)
                VStack(alignment: .leading, spacing: 9) {
                    Text(character.displayName).font(.system(.largeTitle, design: .serif).weight(.regular))
                    Text(character.card.occupation).font(.subheadline).foregroundStyle(ink.opacity(0.65))
                }
            }
            Text(character.card.personality).font(.subheadline).lineSpacing(5)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { interests(character) }
                VStack(alignment: .leading, spacing: 8) { interests(character) }
            }
            Rectangle().fill(ink.opacity(0.15)).frame(height: 0.5).padding(.top, 10)
        }
        .accessibilityIdentifier("activities.encounter.identity")
    }

    private func interests(_ character: CharacterDTO) -> some View {
        ForEach(Array(character.card.hobbies.prefix(3).enumerated()), id: \.offset) { _, hobby in
            Text(hobby).font(.caption).padding(.horizontal, 12).padding(.vertical, 7)
                .background(ink.opacity(0.05), in: Capsule())
        }
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
                Text("两次选择 · 可以告别 · 不消耗金币").font(.caption).foregroundStyle(ink.opacity(0.65))
                primary("出发，给相遇一点时间", id: "activities.action.start") { journey.start() }
            } else {
                if model.summary {
                    summary
                } else {
                    Text(activity.steps[model.step].context).font(.subheadline).foregroundStyle(ink.opacity(0.75))
                    if let reply = model.reply {
                        HStack(alignment: .top, spacing: 4) {
                            TappableText(tokens: TokenCache.tokens(for: reply.english,
                                cacheKey: "social-\(model.runID)-\(model.step)-\(model.selected ?? -1)"),
                                contextID: "social-\(model.runID)", textColor: ink, selection: wordSelection,
                                onSelect: { wordSelection = $0 })
                                .font(.system(.title3, design: .serif))
                                .fixedSize(horizontal: false, vertical: true)
                            Button { model.speak() } label: {
                                Image(systemName: "speaker.wave.2").frame(width: 44, height: 44)
                            }.accessibilityLabel("播放角色语音")
                        }
                        Text(reply.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.72))
                    }
                    if !model.busy && model.error == nil && model.character != nil {
                        Text(activity.steps[model.step].question).font(.headline)
                        choices
                    }
                    if model.selected != nil, model.reply != nil, !model.busy, model.error == nil {
                        primary(model.step == 0 ? "继续" : "回看这次相遇", id: "activities.action.next") { model.advance() }
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

    private var choices: some View {
        ForEach(Array(activity.steps[model.step].choices.enumerated()), id: \.offset) { index, choice in
            if model.selected == nil || model.selected == index {
                Button { model.choose(index) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(choice.english).font(.body.weight(.medium))
                        Text(choice.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.7))
                        if model.selected == index, !choice.response.isEmpty {
                            Text(choice.response).font(.caption).lineSpacing(3)
                                .accessibilityIdentifier("activities.action.feedback")
                        }
                    }
                    .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ink.opacity(model.selected == index ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(DSSceneEntranceButtonStyle())
                    .disabled(model.selected != nil)
                    .accessibilityIdentifier("activities.choice.\(index)")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(activity.closing).font(.system(.title3, design: .serif)).lineSpacing(3)
            ForEach(Array(model.selections.enumerated()), id: \.offset) { index, selected in
                let choice = activity.steps[index].choices[selected]
                VStack(alignment: .leading, spacing: 5) {
                    Text(activity.steps[index].question).font(.caption).foregroundStyle(.secondary)
                    Text(choice.english).font(.subheadline.weight(.medium))
                    Text(model.responses[index]).font(.subheadline).foregroundStyle(ink.opacity(0.75))
                }
            }
            Divider()
            if model.canConnect, let character = model.character {
                Text(character.isFriend ? "你们已经是好友，可以接着聊。" : "对方愿意保持联系。要不要留下这个新的起点？")
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
            primary(saved ? "回到场景" : "记下这次相遇，回到场景", id: "activities.action.finish") {
                do {
                    if !saved {
                        try onComplete(model.selections, model.runID, model.character, model.responses)
                        saved = true
                    }
                    onBack()
                } catch { saveError = "记录未保存，已有数据未改动。请重试。" }
            }
            Text("交流已记入这个人的聊天与记忆；没有自动扣费或建立好友关系。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }
                .font(.headline).padding(18).frame(maxWidth: .infinity)
                .foregroundStyle(Color.dsHologramIvory)
                .background(ink, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(DSSceneEntranceButtonStyle()).accessibilityIdentifier(id)
    }
}
