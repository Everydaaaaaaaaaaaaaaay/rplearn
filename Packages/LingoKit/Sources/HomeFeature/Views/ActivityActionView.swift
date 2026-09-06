import CoreKit
import DesignSystem
import DictKit
import DomainKit
import PersistenceKit
import SpeechKit
import SwiftUI

/// A real private conversation over the shared scene, not a disconnected quiz.
struct ActivityActionView: View {
    let activity: SceneActivity
    let isVisible: Bool
    let onBack: () -> Void
    let onChat: (CharacterDTO) -> Void
    let onComplete: ([Int], UUID, CharacterDTO?, [String]) throws -> Void
    let deps: HomeDependencies
    @StateObject private var model: SocialEncounterModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var saved = false
    @State private var saveError: String?
    @State private var wordSelection: TokenSelection?
    @State private var contentHeight: CGFloat = 0
    private let ink = Color(red: 0.10, green: 0.18, blue: 0.17)

    init(activity: SceneActivity, region: Region, deps: HomeDependencies, isVisible: Bool,
         onBack: @escaping () -> Void, onChat: @escaping (CharacterDTO) -> Void,
         onComplete: @escaping ([Int], UUID, CharacterDTO?, [String]) throws -> Void) {
        self.activity = activity; self.deps = deps; self.isVisible = isVisible
        self.onBack = onBack; self.onChat = onChat; self.onComplete = onComplete
        _model = StateObject(wrappedValue: SocialEncounterModel(activity: activity, region: region, deps: deps))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.opacity(0.23).ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left").font(.title3).frame(width: 44, height: 44)
                        }.accessibilityLabel("返回场景").accessibilityIdentifier("activities.action.back")
                        Text(activity.title).font(.headline)
                        Spacer()
                        Text(model.summary ? "这一刻之后" : model.started ? "轻轻聊两句" : activity.scene.title)
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color.dsHologramIvory)
                    Spacer(minLength: 8)
                    ScrollView {
                        panel
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if abs(contentHeight - height) > 0.5 { contentHeight = height }
                            }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(contentHeight > 0 ? contentHeight : proxy.size.height * 0.72,
                                       proxy.size.height * 0.72))
                    .background(Color(red: 0.98, green: 0.965, blue: 0.91)
                        .opacity(reduceTransparency ? 1 : 0.94), in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, max(proxy.safeAreaInsets.top, 54) + 8)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 24) + 82)
            }
        }
        .ignoresSafeArea().foregroundStyle(ink)
        .animation(DSSceneTransition.animation(reduceMotion: reduceMotion), value: model.step)
        .animation(DSSceneTransition.animation(reduceMotion: reduceMotion), value: model.started)
        .allowsHitTesting(isVisible)
        .onDisappear { model.pause() }
        .onChange(of: isVisible) { _, visible in if !visible { model.pause() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.pause() } }
        .onChange(of: wordSelection != nil) { _, showing in if showing { model.stopSpeech() } }
        .onChange(of: model.reply?.english) { _, _ in
            if isVisible && scenePhase == .active { model.speak() }
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

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.started {
                Text("一次相遇，未必从自我介绍开始。").font(.caption).foregroundStyle(ink.opacity(0.65))
                Text(activity.title).font(.largeTitle.weight(.semibold))
                Text(activity.introduction).lineSpacing(5)
                Text("两次选择 · 可以告别 · 不消耗金币").font(.caption).foregroundStyle(ink.opacity(0.65))
                primary("走近，打个招呼", id: "activities.action.start") { model.start() }
            } else {
                if let character = model.character {
                    HStack(spacing: 14) {
                        AvatarBadge(name: character.card.name, size: 66,
                            imageName: character.card.avatarAssetName,
                            remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                            usesPendingPlaceholder: true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(character.displayName).font(.title2.weight(.semibold))
                            Text(model.alreadyKnown ? "又遇见了 · 身份与之前的交流都还在" : "在各自忙碌的间隙，停下来片刻")
                                .font(.caption).foregroundStyle(ink.opacity(0.65))
                        }
                        Spacer(minLength: 0)
                    }.accessibilityIdentifier("activities.encounter.identity")
                    if model.registrationPending {
                        Text("人物已保留 · 公共身份与头像待同步").font(.caption2).foregroundStyle(.secondary)
                    }
                    Divider()
                }
                if model.summary {
                    summary
                } else {
                    Text(activity.steps[model.step].context).font(.subheadline).foregroundStyle(ink.opacity(0.75))
                    if let reply = model.reply {
                        HStack(alignment: .top, spacing: 4) {
                            TappableText(tokens: TokenCache.tokens(for: reply.english,
                                cacheKey: "social-\(model.runID)-\(model.step)-\(model.selected ?? -1)"),
                                contextID: "social-\(model.runID)", selection: wordSelection,
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
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var choices: some View {
        ForEach(Array(activity.steps[model.step].choices.enumerated()), id: \.offset) { index, choice in
            if model.selected == nil || model.selected == index {
                Button { model.choose(index) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(choice.english).font(.body.weight(.medium))
                        Text(choice.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.7))
                        if model.selected == index {
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
