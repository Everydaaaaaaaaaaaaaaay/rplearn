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
    @Environment(\.tutorialGuideClearance) private var tutorialGuideClearance
    @State private var showsTranslation = false
    @State private var autoReadEnabled = true
    @State private var resultVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var saved = false
    @State private var saveError: String?
    @State private var wordSelection: TokenSelection?
    private let ink = Color.dsTravelNavy

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
        .onDisappear { model.updateAutoReading(enabled: false) }
        .onChange(of: shouldAutoRead) { _, enabled in model.updateAutoReading(enabled: enabled) }
        .onChange(of: progressID) { model.updateAutoReading(enabled: shouldAutoRead) }
        .wordLookupOverlay(selection: $wordSelection, dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                let stopped = model.stopSpeech()
                Task { await stopped?.value; await deps.speech.speak(SpeechRequest(text: word, purpose: .pronunciation)) }
            }, favoriteActions: WordFavoriteActions(
                contains: { (try? await deps.favorites.isWordFavorited($0)) ?? false },
                toggle: { (try? await deps.favorites.toggleWord($0, translationZh: $1)) ?? false }),
            exampleTranslationActions: deps.exampleTranslationActions,
            allowsSystemTranslationFallback: true)
        .overlay(alignment: .topTrailing) {
            if wordSelection != nil {
                Button { wordSelection = nil } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }.accessibilityLabel("关闭释义").padding(.trailing, 16).padding(.top, 6)
            }
        }
    }

    private var sceneName: String {
        switch activity.scene {
        case .park: "Park Break"
        case .pond: "By the Pond"
        case .raincafe: "Rainy Cafe"
        }
    }

    private var navigationHeader: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.accessibilityLabel("返回场景").accessibilityIdentifier("activities.action.back")
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(model.region.nameEn + " · " + sceneName)
                if showsTranslation { Text(model.region.nameZh + " · " + activity.scene.title) }
            }.font(.caption).foregroundStyle(ink.opacity(0.7))
        }
    }

    private var preparationContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    navigationHeader.padding(8)
                        .background { paperSurface(RoundedRectangle(cornerRadius: 20)) }
                    Spacer(minLength: 28)
                    VStack(spacing: 22) {
                        Text(activity.title).font(.largeTitle.weight(.semibold))
                        Text(activity.introduction).font(.body).lineSpacing(6)
                            .foregroundStyle(ink.opacity(0.75))
                        Button { journey.start() } label: {
                            HStack(spacing: 14) { Text("出发"); Image(systemName: "arrow.right") }
                                .font(.headline).padding(.horizontal, 30).padding(.vertical, 17)
                                .foregroundStyle(.white)
                                .background(ink, in: Capsule())
                        }.buttonStyle(DSSceneEntranceButtonStyle())
                            .accessibilityIdentifier("activities.action.start")
                            .tutorialFocus("activity.action", active: deps.tutorial != nil, shape: Capsule())
                            .padding(.top, 10)
                    }
                    .multilineTextAlignment(.center)
                    .padding(26).frame(maxWidth: 480)
                    .background { paperSurface(RoundedRectangle(cornerRadius: 28)) }
                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 38)
                .frame(minHeight: geometry.size.height)
            }.scrollBounceBehavior(.basedOnSize)
        }
        .background { sceneBackdrop }
        .accessibilityIdentifier("activities.confirmation")
    }

    private var resultContent: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.isSolitude {
                        solitudeContent.padding(24).background { paperSurface(RoundedRectangle(cornerRadius: 28)) }
                    } else {
                        panel
                    }
                    Color.clear.frame(height: 1).id("encounter-bottom")
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background {
                Color.clear.contentShape(Rectangle()).onTapGesture { advanceIfAllowed() }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 22)
                    Rectangle().fill(.black)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: progressID) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    reader.scrollTo("encounter-bottom", anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }.accessibilityLabel("返回场景").accessibilityIdentifier("activities.action.back")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.region.nameEn).font(.caption.weight(.semibold))
                        Text(sceneName).font(.caption2).foregroundStyle(ink.opacity(0.6))
                    }
                    Spacer(minLength: 4)
                    translationAndSpeech
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background { paperSurface(Rectangle()) }
                if !model.isSolitude, let character = model.character {
                    identity(character).padding(.horizontal, 22)
                }
            }
        }
        .tint(ink)
        .background { sceneBackdrop }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activities.result")
        .onAppear { resultVisible = true; model.updateAutoReading(enabled: shouldAutoRead) }
        .onDisappear { resultVisible = false; model.updateAutoReading(enabled: false) }
    }

    private var sceneBackdrop: some View {
        ActivitySceneView(isVisible: false, showsInterface: false,
            scene: .constant(activity.scene), cityName: model.region.nameZh,
            completedCount: 0, onClose: {}, onJournal: {}, onSelect: { _ in })
            .blur(radius: 10, opaque: true)
            .overlay(Color.white.opacity(0.26))
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }

    private var shouldAutoRead: Bool {
        autoReadEnabled && resultVisible && isVisible && scenePhase == .active && wordSelection == nil
    }

    private var progressID: String {
        "\(model.step)-\(model.beatIndex)-\(model.summary)-\(showsTranslation)"
    }

    /// 阅读页的纸面控件。场景照在两种外观下都是亮的，正文墨色也固定为纸面深蓝，
    /// 材质若跟随深色外观就会压成深灰，和墨色叠成一片、读不清（教程里尤其明显）。
    /// 固定为浅色材质，等价于正文区已有的白色纸卡外观。
    private func paperSurface<S: Shape>(_ shape: S) -> some View {
        shape.fill(.regularMaterial)
            .environment(\.colorScheme, .light)
    }

    private func advanceIfAllowed() {
        guard isVisible, wordSelection == nil, !model.busy, model.error == nil,
              !model.atChoice, !model.summary else { return }
        model.advance()
    }

    private func identity(_ character: CharacterDTO) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                AvatarBadge(name: character.card.name, size: 52, imageName: character.card.avatarAssetName,
                    remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                    .padding(5).background(.white.opacity(0.8), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(character.displayName).font(.system(.title2, design: .rounded, weight: .bold))
                    lookupText(character.card.occupation, key: "occupation")
                        .font(.subheadline).foregroundStyle(ink.opacity(0.65))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { paperSurface(RoundedRectangle(cornerRadius: 28)) }
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.65)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activities.encounter.identity")
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

    private var translationAndSpeech: some View {
        HStack(spacing: 4) {
            Button { showsTranslation.toggle() } label: {
                Image(systemName: "translate").frame(width: 44, height: 44)
                    .background(showsTranslation ? ink.opacity(0.1) : .clear, in: Circle())
            }
            .accessibilityLabel("中文翻译").accessibilityValue(showsTranslation ? "开启" : "关闭")
            .accessibilityIdentifier("activities.story.translation")
            Button { autoReadEnabled.toggle() } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(autoReadEnabled ? Color.dsSkyDeep : ink.opacity(0.35))
                    .frame(width: 44, height: 44)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: autoReadEnabled)
            .accessibilityLabel("自动朗读新剧情").accessibilityValue(autoReadEnabled ? "开启" : "关闭")
            .accessibilityIdentifier("activities.story.play")
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let chapter = model.chapters.first {
                VStack(alignment: .leading, spacing: 10) {
                    lookupText(chapter.titleEnglish ?? "A Map in the Wind", key: "title")
                    if showsTranslation {
                        Text(chapter.title).foregroundStyle(ink.opacity(0.72))
                    }
                }.font(.system(.title, design: .serif, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("THE MOMENT").font(.caption2.weight(.bold)).tracking(1.7)
                if showsTranslation { Text("此刻").font(.caption2.weight(.bold)) }
            }.foregroundStyle(ink.opacity(0.6))
            ForEach(Array(model.chapters.enumerated()), id: \.offset) { stage, chapter in
                ForEach(Array(chapter.beats.enumerated()), id: \.offset) { index, beat in
                    if stage < model.step || (stage == model.step && index <= model.beatIndex) {
                        beatRow(beat, stage: stage, index: index)
                    }
                }
                if stage < model.selections.count {
                    let choice = chapter.choices[model.selections[stage]]
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.turn.down.right").font(.caption)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(choice.english).font(.subheadline.weight(.semibold))
                            if showsTranslation { Text(choice.chinese).font(.subheadline.weight(.semibold)) }
                        }
                    }.foregroundStyle(ink.opacity(0.7)).padding(.vertical, 8)
                }
            }
            if model.summary {
                if tutorialGuideClearance > 0 {
                    Color.clear.frame(height: tutorialGuideClearance).accessibilityHidden(true)
                }
                summary
            } else if !model.busy, model.error == nil {
                if model.atChoice {
                    if tutorialGuideClearance > 0 {
                        Color.clear.frame(height: tutorialGuideClearance).accessibilityHidden(true)
                    }
                    choices
                }
                else {
                    Button(action: advanceIfAllowed) {
                        TapToContinueHint(showsTranslation: showsTranslation)
                    }.buttonStyle(.plain).accessibilityIdentifier("activities.action.next")
                        .anchorPreference(key: TutorialTargetPreference.self, value: .bounds) { ["activity.continue": $0] }
                }
            }
            if model.busy {
                ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("activities.encounter.loading")
            }
            if let error = model.error {
                Text(error).font(.callout)
                Button("重试，不更换人物") { model.retry() }
                    .accessibilityIdentifier("activities.encounter.retry")
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28).fill(Color.white.opacity(0.90))
                .onTapGesture { advanceIfAllowed() }
        }
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.7)))
    }

    private func beatRow(_ beat: EncounterChapter.Beat, stage: Int, index: Int) -> some View {
        let isNarration = beat.speaker != "npc"
        return VStack(alignment: .leading, spacing: 10) {
            if !isNarration {
                Text(model.character?.displayName ?? "Companion")
                    .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(ink.opacity(0.52))
            }
            lookupText(beat.english, key: "beat-\(stage)-\(index)")
                .font(isNarration ? .system(.body, design: .serif) : .system(.title3, design: .serif))
                .lineSpacing(6)
            if showsTranslation {
                Text(beat.chinese).font(isNarration ? .system(.body, design: .serif) : .system(.title3, design: .serif)).lineSpacing(6).foregroundStyle(ink.opacity(0.62))
            }
        }
        .padding(.leading, isNarration ? 14 : 0)
        .overlay(alignment: .leading) {
            if isNarration { RoundedRectangle(cornerRadius: 1).fill(ink.opacity(0.15)).frame(width: 2) }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activities.beat.\(stage).\(index)")
    }

    private func lookupText(_ text: String, key: String) -> some View {
        TappableText(tokens: TokenCache.tokens(for: text, cacheKey: "chapter-\(model.runID)-\(key)"),
            contextID: "chapter-\(model.runID)-\(key)", textColor: ink, selection: wordSelection, lookupOnLongPress: false,
            onSelect: { wordSelection = $0 }).fixedSize(horizontal: false, vertical: true)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR MOVE").font(.caption.weight(.bold)).tracking(1.8)
                if showsTranslation { Text("你想怎么做？").font(.caption.weight(.bold)) }
            }.foregroundStyle(ink.opacity(0.55)).padding(.top, 12).padding(.bottom, 4)
            ForEach(Array(model.chapters[model.step].choices.enumerated()), id: \.offset) { index, choice in
                Button { model.choose(index) } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(ink.opacity(0.4))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(choice.english).font(.system(.body, design: .rounded, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if showsTranslation {
                                Text(choice.chinese).font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(ink.opacity(0.65))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                    }
                    .multilineTextAlignment(.leading).padding(18)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ink.opacity(0.14)))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(DSSceneEntranceButtonStyle()).disabled(model.selected != nil || model.busy)
                .accessibilityIdentifier("activities.choice.\(index)")
                .tutorialFocus("activity.action", active: deps.tutorial != nil && index == 0)
            }
        }
        .anchorPreference(key: TutorialTargetPreference.self, value: .bounds) { ["activity.action": $0] }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .anchorPreference(key: TutorialTargetPreference.self, value: .bounds) { ["activity.action": $0] }
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }
                .font(.headline).padding(18).frame(maxWidth: .infinity)
                .foregroundStyle(Color.white)
                .background(Color.dsTravelNavy, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(DSSceneEntranceButtonStyle()).accessibilityIdentifier(id)
            .tutorialFocus("activity.action", active: deps.tutorial != nil && id == "activities.action.start")
    }
}
