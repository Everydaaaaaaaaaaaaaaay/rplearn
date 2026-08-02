import AVFoundation
import CoreKit
import DesignSystem
import Foundation
import Observation
import PersistenceKit
import RealtimeVoiceKit
import SpeechKit
import SwiftUI
import UIKit

@MainActor
@Observable
private final class RealtimeConversationCoordinator {
    let chat: ChatViewModel
    let session: RealtimeVoiceSession
    private let speech: any SpeechService

    init(chat: ChatViewModel, deps: ChatDependencies) {
        let character = chat.character
        let client = RealtimeVoiceConversationClient(
            replyStream: { [weak chat] text in
                guard let chat else {
                    throw AppError.storage("实时语音会话已结束")
                }
                return try await chat.realtimeReplyStream(userText: text)
            },
            saveAssistant: { [weak chat] text in
                await chat?.saveRealtimeAssistant(spokenText: text)
            }
        )
        let language = AccentMapper.language(forNationality: character.card.nationality)
        self.chat = chat
        self.session = RealtimeVoiceSession(
            audioSession: deps.audioSession,
            conversation: client,
            localeIdentifier: "en-US",
            voiceLanguage: language,
            contextualStrings: Self.contextualStrings(for: character),
            turnPolicy: Self.turnPolicy(for: character.difficultyLevel)
        )
        self.speech = deps.speech
    }

    func start() async {
        await speech.stopSpeaking()
        if chat.conversation == nil {
            await chat.load()
        }
        await session.start()
    }

    private static func contextualStrings(for character: CharacterDTO) -> [String] {
        [character.card.name, character.card.regionID, character.card.occupation]
            + character.card.hobbies
    }

    private static func turnPolicy(for level: DifficultyLevel) -> VoiceTurnDetectionPolicy {
        let silence: TimeInterval
        switch level {
        case .primary1, .primary2, .primary3, .primary4, .primary5, .primary6:
            silence = 1.05
        case .junior1, .junior2, .junior3:
            silence = 0.9
        case .senior1, .senior2, .senior3:
            silence = 0.8
        case .undergraduate, .postgraduate, .advanced:
            silence = 0.7
        }
        return VoiceTurnDetectionPolicy(endOfTurnSilence: silence)
    }
}

/// 单角色实时语音页。保持轻量品牌露出，不把聊天页改造成传统电话界面。
struct RealtimeConversationView: View {
    @State private var coordinator: RealtimeConversationCoordinator
    @State private var debugText = "What do you like about this city?"
    @State private var showsDebugInput = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onSpeechPlayback: () -> Void

    init(
        chat: ChatViewModel,
        deps: ChatDependencies,
        onSpeechPlayback: @escaping () -> Void
    ) {
        _coordinator = State(
            initialValue: RealtimeConversationCoordinator(
                chat: chat,
                deps: deps
            )
        )
        self.onSpeechPlayback = onSpeechPlayback
    }

    private var session: RealtimeVoiceSession { coordinator.session }
    private var character: CharacterDTO { coordinator.chat.character }

    var body: some View {
        ZStack {
            Color.dsBackground.ignoresSafeArea()
            LinearGradient(
                colors: [Color.dsSky.opacity(0.12), .clear, Color.dsBrandCream.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 22) {
                        presence
                        transcriptPanel
                        privacyNote
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .padding(.bottom, DSSpacing.sm)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                controls
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.lg)
        }
        .task {
            await coordinator.start()
        }
        .onChange(of: scenePhase) { _, newValue in
            Task {
                switch newValue {
                case .background:
                    await session.suspend()
                case .active where session.phase == .paused:
                    await session.resume()
                default:
                    break
                }
            }
        }
        .onChange(of: session.phase) { _, newValue in
            if newValue == .speaking {
                onSpeechPlayback()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
        ) { notification in
            handleAudioInterruption(notification)
        }
        .onDisappear {
            Task { await session.stop() }
        }
        #if targetEnvironment(simulator)
        .alert("模拟实时语音", isPresented: $showsDebugInput) {
            TextField("英文转写", text: $debugText)
            Button("发送") {
                session.submitDebugTurn(debugText)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("模拟器麦克风不稳定时，可直接验证流式回复和本地播报。")
        }
        #endif
    }

    private var topBar: some View {
        HStack {
            Button {
                Task {
                    await session.stop()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel("结束语音对话")

            Spacer()

            VStack(spacing: 2) {
                Text(character.card.name)
                    .font(.headline)
                Text("实时英语对话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            #if targetEnvironment(simulator)
            Button {
                showsDebugInput = true
            } label: {
                Image(systemName: "hammer")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel("模拟一句语音")
            #else
            Color.clear.frame(width: 44, height: 44)
            #endif
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            Task {
                await session.suspend()
            }
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                .contains(.shouldResume)
            Task {
                if shouldResume, session.phase == .paused {
                    await session.resume()
                }
            }
        @unknown default:
            break
        }
    }

    private var presence: some View {
        VStack(spacing: DSSpacing.md) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.dsSky.opacity(0.1 + session.inputLevel * 0.12))
                    .frame(width: 142, height: 142)
                    .scaleEffect(1 + session.inputLevel * 0.12)
                    .animation(reduceMotion ? nil : DSAnimation.feedback, value: session.inputLevel)
                AvatarBadge(name: character.card.name, size: 104)
                BrandMascotView(pose: .coach, size: 38, showsShadow: false)
                    .padding(2)
                    .background(Color.dsSurface, in: Circle())
                    .accessibilityHidden(true)
            }

            VStack(spacing: 4) {
                Text(statusTitle)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .animation(reduceMotion ? nil : DSAnimation.snappy, value: session.phase)
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            transcriptRow(
                label: "你",
                text: session.liveTranscript.isEmpty
                    ? session.userTranscript
                    : session.liveTranscript,
                tint: .dsSky
            )
            Divider()
            transcriptRow(
                label: character.card.name,
                text: session.assistantTranscript,
                tint: .dsBrandCoral
            )

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(session.phase == .failed ? Color.dsDanger : .secondary)

                if session.phase == .failed {
                    HStack(spacing: DSSpacing.sm) {
                        Button("再试一次") {
                            Task { await session.start() }
                        }
                        .buttonStyle(.borderedProminent)

                        if session.requiresSettings {
                            Button("打开设置") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
                .stroke(Color.dsBorder.opacity(0.7), lineWidth: 1)
        }
    }

    private func transcriptRow(label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(text.isEmpty ? "…" : text)
                .font(.body)
                .foregroundStyle(text.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .combine)
    }

    private var privacyNote: some View {
        Label("AI 角色只会收到转写文字，不会收到原始录音", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, DSSpacing.md)
    }

    private var controls: some View {
        HStack(spacing: 32) {
            Button {
                Haptics.selection()
                session.toggleMuted()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: session.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.title3)
                        .frame(width: 54, height: 54)
                        .background(.thinMaterial, in: Circle())
                    Text(session.isMuted ? "打开麦克风" : "静音")
                        .font(.caption)
                }
            }
            .buttonStyle(.pressableCard)
            .disabled(session.phase == .connecting || session.phase == .failed)

            Button {
                Haptics.impact(.medium)
                Task {
                    await session.stop()
                    dismiss()
                }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(Color.dsBrandCoral, in: Circle())
                    .shadow(color: Color.dsBrandCoral.opacity(0.24), radius: 12, y: 5)
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel("结束语音对话")
        }
    }

    private var statusTitle: String {
        if session.isMuted { return "麦克风已关闭" }
        return switch session.phase {
        case .idle: "已结束"
        case .connecting: "正在连接…"
        case .listening: "我在听"
        case .thinking: "\(character.card.name) 正在想"
        case .speaking: "\(character.card.name) 正在说"
        case .paused: "对话已暂停"
        case .failed: "暂时无法开始"
        }
    }

    private var statusDetail: String {
        if session.isMuted { return "点按下方按钮即可继续" }
        return switch session.phase {
        case .idle: "这次对话已经保存到聊天记录"
        case .connecting: "正在准备本地麦克风与语音识别"
        case .listening: "自然说英语即可，不需要按住按钮"
        case .thinking: "你可以继续说来打断这次回复"
        case .speaking: "直接开口就能自然插话"
        case .paused: "回到应用后会在这里恢复"
        case .failed: "可在当前页面重试，仍失败时请检查网络与系统权限"
        }
    }
}
