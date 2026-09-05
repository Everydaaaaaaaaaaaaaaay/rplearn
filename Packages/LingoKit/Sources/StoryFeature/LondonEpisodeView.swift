import AVFoundation
import CoreKit
import DesignSystem
import DictKit
import Foundation
import SpeechKit
import StoryEngine
import SwiftUI
import UIKit

/// Opt-in preview: no rewards, roster mutations or legacy story checkpoints.
public struct LondonEpisodeView: View {
    private let deps: StoryDependencies
    private let storageKey: String
    @State private var session: EpisodeSession?
    @State private var art: [String: UIImage] = [:]
    @State private var loadError = false
    @State private var showTranslation = true
    @State private var automatic = false
    @State private var showHistory = false
    @State private var showHistoryRestart = false
    @State private var showRestart = false
    @State private var wordSelection: TokenSelection?
    @State private var audio: NarrativeAudioPlayer
    @State private var soundEnabled = true
    @State private var spokenStarts = 0
    @State private var narratedNodeID: String?
    @State private var lastAudioPageID: String?
    @State private var currentLineIsVoiced = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let ink = Color(red: 0.13, green: 0.19, blue: 0.18)
    private let paper = Color(red: 0.98, green: 0.96, blue: 0.90)
    private let gold = Color(red: 0.84, green: 0.68, blue: 0.40)

    public init(deps: StoryDependencies, storageNamespace: String = "guest") {
        self.deps = deps
        _audio = State(initialValue: NarrativeAudioPlayer(speech: deps.speech, audioSession: deps.audioSession))
        #if DEBUG
        _soundEnabled = State(initialValue: ProcessInfo.processInfo.environment["UI_TEST_EPISODE_AUDIO"] != "0")
        if ProcessInfo.processInfo.environment["UI_TEST_LONDON_EPISODE"] == "1" {
            storageKey = "story.preview.departures.london.v1.uitest"
            return
        }
        #endif
        storageKey = "story.preview.departures.london.v1.\(storageNamespace)"
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let session {
                    VStack(spacing: 0) {
                        header(session)
                        Spacer(minLength: 12)
                        if session.nodeID == session.episode.start && !dynamicTypeSize.isAccessibilitySize {
                            openingTitle
                                .padding(.bottom, 20)
                        }
                        readingPanel(session, maxHeight: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.78 : session.isFinished ? 0.76 : 0.53))
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 18)
                } else if loadError {
                    ContentUnavailableView {
                        Label("样章暂时无法载入", systemImage: "book.closed")
                    } description: {
                        Text("剧情或美术资源缺失。请返回后重试。")
                    } actions: { Button("返回剧情") { dismiss() } }
                    .foregroundStyle(paper)
                } else {
                    ProgressView("正在打开这一页…").tint(paper).foregroundStyle(paper)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            // Artwork fills the screen without proposing its oversized dimensions
            // to the controls. Only this background, not the reading UI, ignores safe areas.
            .background {
                GeometryReader { backdrop in
                    if let session {
                        stage(session, size: backdrop.size)
                    } else {
                        Color(red: 0.06, green: 0.10, blue: 0.10)
                    }
                }
                .ignoresSafeArea()
            }
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                guard value.startLocation.x < 28, value.translation.width > 70,
                      abs(value.translation.height) < value.translation.width * 0.6,
                      wordSelection == nil else { return }
                dismiss()
            })
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .task(id: autoplayIdentity) { await autoplay() }
        .onChange(of: audioIdentity, initial: true) { _, _ in updateAudio() }
        .onDisappear { audio.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue {
                soundEnabled = false
                automatic = false
                audio.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                soundEnabled = false
                automatic = false
                audio.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .speechPlaybackDidBegin)) { _ in
            spokenStarts += 1
        }
        .wordLookupOverlay(
            selection: $wordSelection,
            dictionary: deps.dictionary,
            grammar: deps.grammarPoints,
            onSpeak: { word in
                audio.play(id: "lookup", request: SpeechRequest(text: word, language: "en-US", purpose: .pronunciation),
                           rainVolume: 0, pageTurn: false)
            },
            favoriteActions: WordFavoriteActions(
                contains: { (try? await deps.favorites.isWordFavorited($0)) ?? false },
                toggle: { (try? await deps.favorites.toggleWord($0, translationZh: $1)) ?? false }
            ),
            exampleTranslationActions: deps.exampleTranslationActions,
            allowsSystemTranslationFallback: true
        )
        .sheet(isPresented: $showHistory) { historySheet }
        .confirmationDialog("从头开始这一站？当前样章进度将被替换。", isPresented: $showRestart, titleVisibility: .visible) {
            Button("从头开始", role: .destructive) { restart() }
            Button("取消", role: .cancel) { }
        }
    }

    private func stage(_ session: EpisodeSession, size: CGSize) -> some View {
        ZStack {
            if let image = art[session.shot.background] {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                    .id(session.shot.background)
                    .transition(.opacity)
            }
            ForEach(session.shot.actors, id: \.id) { actor in
                if let image = art[actor.asset] {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(height: min(size.height * 0.75, size.width * 1.64) * actor.scale)
                        .position(x: size.width * actor.x, y: size.height * 0.51)
                        .id(actor.asset)
                        .transition(.opacity)
                }
            }
            LinearGradient(colors: [.black.opacity(0.38), .clear, .clear, .black.opacity(0.38)],
                           startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: reduceMotion ? 0.10 : 0.28), value: session.shot)
    }

    private func header(_ session: EpisodeSession) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("返回剧情")
                .accessibilityIdentifier("episode.close")
                VStack(alignment: .leading, spacing: 4) {
                    Text("出发之后  /  LONDON").font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(gold)
                    Text(session.episode.acts[session.current.act]).font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 0)
                Button {
                    soundEnabled.toggle()
                    // Explicitly enabling voice can replay; dismissing a lookup cannot.
                    if soundEnabled { narratedNodeID = nil }
                } label: {
                    Image(systemName: soundEnabled ? "speaker.wave.2" : "speaker.slash")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(soundEnabled ? "关闭剧情声音" : "开启剧情声音")
                .accessibilityIdentifier("episode.sound")
                .accessibilityValue(audioAccessibilityValue)
                Button { showHistory = true } label: {
                    Image(systemName: "text.book.closed").frame(width: 44, height: 44)
                }.accessibilityLabel("回看对话").accessibilityIdentifier("episode.history")
                Button { automatic.toggle() } label: {
                    Image(systemName: automatic ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                }.accessibilityLabel(automatic ? "暂停自动播放" : "自动播放").accessibilityIdentifier("episode.auto")
            }
            HStack(spacing: 5) {
                ForEach(session.episode.acts.indices, id: \.self) { index in
                    Rectangle().fill(index <= session.current.act ? gold : paper.opacity(0.22)).frame(height: 2)
                }
            }.padding(.horizontal, 9).accessibilityHidden(true)
        }
        .foregroundStyle(paper)
        .buttonStyle(EpisodePressStyle())
    }

    private var openingTitle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("第一站 · 伦敦").font(.caption.weight(.medium)).tracking(3).foregroundStyle(gold)
            Text("空着的\n那把椅子").font(.system(size: 38, weight: .medium, design: .serif))
                .foregroundStyle(paper).lineSpacing(5)
            Text("A PLACE FOR ONE PAGE").font(.system(size: 10)).tracking(3).foregroundStyle(paper.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10)
        .accessibilityIdentifier("episode.title")
    }

    private func readingPanel(_ session: EpisodeSession, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(session.current.speaker).font(.subheadline.weight(.semibold))
                Spacer()
                Button { showTranslation.toggle() } label: {
                    Text(showTranslation ? "中 / EN" : "EN").font(.caption.weight(.medium))
                        .frame(minWidth: 52, minHeight: 44)
                }.accessibilityLabel(showTranslation ? "隐藏中文翻译" : "显示中文翻译")
                    .accessibilityIdentifier("episode.translation")
            }
            .foregroundStyle(ink)
            Rectangle().fill(gold.opacity(0.6)).frame(height: 1).padding(.bottom, 14)
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TappableText(
                            tokens: TokenCache.tokens(for: session.isFinished ? "“\(session.current.text)”" : session.current.text,
                                                      cacheKey: "episode-quoted-\(session.nodeID)"),
                            contextID: "episode-\(session.nodeID)", textColor: ink, selection: wordSelection,
                            onSelect: { selection in
                                // An outgoing line may remain visible for a few frames.
                                guard self.session?.nodeID == session.nodeID else { return }
                                wordSelection = selection
                            }
                        )
                        .font(session.isFinished
                              ? .custom("Baskerville-Italic", size: 32, relativeTo: .title2)
                              : .system(.body, design: .serif))
                        // The app-wide rounded design otherwise replaces the custom face.
                        .fontDesign(session.isFinished ? nil : .rounded)
                        .italic(session.isFinished)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("episode.line")
                        if showTranslation {
                            Text(session.current.translation).font(.subheadline).lineSpacing(5)
                                .foregroundStyle(ink.opacity(0.77)).fixedSize(horizontal: false, vertical: true)
                        }
                        if let choices = session.current.choices {
                            ForEach(choices) { choice in
                                Button { choose(choice.id) } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("↗").foregroundStyle(gold)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(choice.text).font(.subheadline.weight(.medium))
                                            if showTranslation { Text(choice.translation).font(.caption).opacity(0.75) }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(ink).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(gold.opacity(0.5), lineWidth: 1))
                                }.buttonStyle(EpisodePressStyle())
                                    .accessibilityIdentifier("episode.choice.\(choice.id)")
                            }
                        }
                        if session.isFinished { endingSummary(session) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: maxHeight - (session.isFinished ? 178 : 120))
                .fixedSize(horizontal: false, vertical: true)
                .id(session.nodeID)
                .transition(.opacity)
            }
            // Crossfade only the reading content, keeping the surface and Continue
            // control alive. No delayed navigation, input lock or background flash.
            .animation(.easeInOut(duration: reduceMotion ? 0.08 : 0.12), value: session.nodeID)

            if session.isFinished {
                Button { dismiss() } label: {
                    Label("结束旅程", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(paper)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(ink, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(EpisodePressStyle())
                .accessibilityIdentifier("episode.finish")
                .padding(.top, 12)
            }

            HStack {
                Text(session.isFinished ? "本设备已保存 · 样章不发放奖励" : "轻点英文可查词")
                    .font(.system(size: 10)).foregroundStyle(ink.opacity(0.55))
                Spacer(minLength: 4)
                if session.current.choices == nil {
                    Button {
                        if session.isFinished { showRestart = true } else { advance() }
                    } label: {
                        HStack(spacing: 8) {
                            Text(session.isFinished ? "重走这一站" : "继续").font(.subheadline.weight(.medium))
                            Image(systemName: session.isFinished ? "arrow.counterclockwise" : "arrow.right").font(.caption)
                        }.foregroundStyle(ink).frame(minWidth: 72, minHeight: 44)
                    }.buttonStyle(EpisodePressStyle())
                        .accessibilityIdentifier(session.isFinished ? "episode.restart" : "episode.next")
                }
            }.padding(.top, 8)
        }
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 8)
        .background(paper.opacity(reduceTransparency || contrast == .increased ? 1 : 0.88),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(contrast == .increased ? ink.opacity(0.35) : .white.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .environment(\.colorScheme, .light)
    }

    private func endingSummary(_ session: EpisodeSession) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Rectangle().fill(ink.opacity(0.14)).frame(height: 1)
                .padding(.top, 8).accessibilityHidden(true)
            Text("这一晚，你留下的选择")
                .font(.headline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(session.decisionRecords) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.context).font(.caption.weight(.semibold))
                            .foregroundStyle(ink.opacity(0.65))
                        Text(record.choice).font(.subheadline.weight(.medium))
                        if let outcome = record.outcome {
                            Text("本章影响：\(outcome)").font(.caption).lineSpacing(3)
                                .foregroundStyle(ink.opacity(0.77))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("episode.review.\(record.id)")
                }
            }
        }.foregroundStyle(ink)
    }

    private var historySheet: some View {
        NavigationStack {
            ScrollView {
                if let session {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(session.history + [session.nodeID], id: \.self) { id in
                            if let node = session.episode.node(id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(node.speaker).font(.caption.bold()).foregroundStyle(gold)
                                    Text(node.text).font(.body)
                                    Text(node.translation).font(.subheadline).foregroundStyle(.secondary)
                                    if let chosen = session.decisions[id], let choice = node.choices?.first(where: { $0.id == chosen }) {
                                        Text("↗ \(choice.translation)").font(.caption).foregroundStyle(gold)
                                    }
                                }
                            }
                        }
                    }.padding(24)
                }
            }.navigationTitle("这一晚的对话").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("继续阅读") { showHistory = false } }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("重玩") { showHistoryRestart = true }
                    }
                }
                .confirmationDialog("从头开始这一站？", isPresented: $showHistoryRestart, titleVisibility: .visible) {
                    Button("从头开始", role: .destructive) { restart(); showHistory = false }
                    Button("取消", role: .cancel) { }
                }
        }
    }

    private var canAutoAdvance: Bool {
        automatic && scenePhase == .active && wordSelection == nil && !showHistory && !showRestart
            && session?.current.choices == nil && session?.isFinished == false
            && (!soundEnabled || audio.completedID == session?.nodeID)
    }
    private var autoplayIdentity: String { "\(session?.nodeID ?? "")-\(canAutoAdvance)" }

    private func autoplay() async {
        guard canAutoAdvance, let current = session?.current else { return }
        let delay = soundEnabled && currentLineIsVoiced ? 0.6 : max(4.0, Double(current.text.split(separator: " ").count) * 0.42)
        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        guard !Task.isCancelled, canAutoAdvance, session?.nodeID == current.id else { return }
        advance()
    }

    private var audioAccessibilityValue: String {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_LONDON_EPISODE"] == "1" {
            return "starts:\(spokenStarts);completed:\(audio.completedID ?? "none")"
        }
        #endif
        return soundEnabled ? "角色配音与环境声已开启" : "剧情静音，查词仍可单独播放"
    }

    private var canPlayAudio: Bool {
        soundEnabled && scenePhase == .active && wordSelection == nil && !showHistory && !showRestart
    }
    private var audioIdentity: String { "\(session?.nodeID ?? "")-\(canPlayAudio)" }

    private func updateAudio() {
        let newPage = lastAudioPageID != session?.nodeID
        lastAudioPageID = session?.nodeID
        guard canPlayAudio, let session else { audio.stop(); return }
        let speaker = session.current.speaker
        // Keep the pilot on the bundled engine regardless of the global setting.
        // Supertonic exposes English, not a guaranteed British accent.
        let identity = speaker == "Oliver" ? "london.oliver" : speaker == "Nora" ? "london.nora"
            : "london.narrator"
        let request = SpeechRequest(text: session.current.text, language: "en", purpose: .characterDialogue,
                                    voiceHint: SpeechVoiceHint(stableID: identity,
                                                              gender: speaker == "Oliver" ? "male" : "female"),
                                    engine: .supertonic3)
        currentLineIsVoiced = speaker != "你" && session.current.choices == nil && narratedNodeID != session.nodeID
        if currentLineIsVoiced { narratedNodeID = session.nodeID }
        // The rain has stopped at the ending; inside, only distant window rain.
        let rain: Float = session.current.act == 5 ? 0 : session.shot.background == "london_exterior" ? 0.25 : 0.06
        audio.play(id: session.nodeID, request: currentLineIsVoiced ? request : nil,
                   rainVolume: rain, pageTurn: newPage && session.nodeID != session.episode.start)
    }

    private func save() {
        guard let cp = session?.checkpoint, let data = try? JSONEncoder().encode(cp) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    private func advance() {
        session?.advance()
        if session?.isFinished == true { automatic = false }
        save()
    }
    private func choose(_ id: String) {
        session?.choose(id); save()
    }
    private func restart() {
        guard let episode = session?.episode else { return }
        automatic = false
        narratedNodeID = nil
        lastAudioPageID = nil
        session = EpisodeSession(episode: episode)
        save()
    }

    private func load() async {
        guard session == nil else { return }
        do {
            guard let url = Bundle.main.url(forResource: "departures_london_v1", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let episode = try StoryEpisode.load(data: Data(contentsOf: url))
            // This one-station preview is bounded to eight images (~48 MiB decoded).
            // Prepare them off-main once; never decode or read disk on a dialogue tap.
            let names = episode.assetNames
            guard names.count <= 8 else { throw CocoaError(.fileReadTooLarge) }
            let loaded = try await Task.detached(priority: .userInitiated) {
                var images: [String: UIImage] = [:]
                for name in names {
                    guard let url = Bundle.main.url(forResource: name, withExtension: name.hasPrefix("oliver") || name.hasPrefix("nora") ? "png" : "jpg"),
                          let image = UIImage(contentsOfFile: url.path) else { throw CocoaError(.fileNoSuchFile) }
                    images[name] = image.preparingForDisplay() ?? image
                }
                return EpisodeArtwork(images: images)
            }.value
            guard !Task.isCancelled else { return }
            art = loaded.images
            var saved = UserDefaults.standard.data(forKey: storageKey)
            #if DEBUG
            if ProcessInfo.processInfo.environment["UI_TEST_EPISODE_FRESH"] == "1" { saved = nil }
            #endif
            session = EpisodeSession(episode: episode, saved: saved)
        } catch { loadError = true }
    }
}

// Immutable, fully prepared UIImages cross the worker→main boundary once.
private struct EpisodeArtwork: @unchecked Sendable {
    let images: [String: UIImage]
}

private struct EpisodePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.spring(response: 0.20, dampingFraction: 0.90), value: configuration.isPressed)
    }
}
