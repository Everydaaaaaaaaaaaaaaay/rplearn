import BackendKit
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
    private let accessClient: BackendClient?
    var accessError: String?
    private var leaseTask: Task<Void, Never>?
    private var stopped = false

    init(chat: ChatViewModel, deps: ChatDependencies) {
        let character = chat.character
        let conversation = RealtimeVoiceConversationClient(
            replyStream: { [weak chat] text in
                guard let chat else { throw AppError.storage("实时语音会话已结束") }
                return try await chat.realtimeReplyStream(userText: text)
            },
            saveAssistant: { [weak chat] text, interrupted in
                await chat?.saveRealtimeAssistant(
                    spokenText: text,
                    interrupted: interrupted
                )
            }
        )
        let language = AccentMapper.language(forNationality: character.card.nationality)
        let voiceHint = SpeechVoiceHint(
            stableID: character.id.uuidString.lowercased(),
            gender: character.card.gender.rawValue,
            nationality: character.card.nationality
        )
        self.accessClient = deps.accessClient
        self.chat = chat
        self.session = RealtimeVoiceSession(
            audioSession: deps.audioSession,
            speech: deps.speech,
            conversation: conversation,
            voiceLanguage: language,
            voiceHint: voiceHint,
            turnPolicy: Self.turnPolicy(for: character.difficultyLevel)
        )
        self.speech = deps.speech
    }

    func start() async {
        await speech.stopSpeaking()
        if chat.conversation == nil {
            await chat.load()
        }
        stopped = false
        if accessClient != nil {
            do { try await renewLease() }
            catch { accessError = error.localizedDescription; return }
        }
        guard !stopped else { return }
        await session.start()
    }

    func stop() async {
        stopped = true
        leaseTask?.cancel()
        leaseTask = nil
        await session.stop()
        if let id = chat.voiceLeaseID {
            chat.voiceLeaseID = nil
            try? await accessClient?.stopVoice(operationID: id)
        }
    }

    private func renewLease() async throws {
        guard let accessClient else { return }
        if let previous = chat.voiceLeaseID {
            try await accessClient.stopVoice(operationID: previous)
            chat.voiceLeaseID = nil
        }
        let operationID = UUID()
        let lease: BackendVoiceLease
        do { lease = try await accessClient.reserveVoice(operationID: operationID) }
        catch {
            try? await accessClient.stopVoice(operationID: operationID)
            throw error
        }
        guard !stopped else {
            try? await accessClient.stopVoice(operationID: lease.operationId)
            return
        }
        chat.voiceLeaseID = lease.operationId
        leaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(lease.amount))
                guard let self, !self.stopped else { return }
                try await self.renewLease()
            } catch is CancellationError { return }
            catch {
                guard let self else { return }
                self.accessError = error.localizedDescription
                await self.stop()
            }
        }
    }

    private static func turnPolicy(for level: DifficultyLevel) -> VoiceTurnPolicy {
        let fallbackDelay: Duration = switch level {
        case .kindergarten, .primary1, .primary2, .primary3, .primary4, .primary5, .primary6:
            .milliseconds(1_350)
        case .junior1, .junior2, .junior3:
            .milliseconds(1_200)
        case .senior1, .senior2, .senior3:
            .milliseconds(1_100)
        case .undergraduate, .postgraduate, .advanced:
            .milliseconds(1_000)
        }
        return VoiceTurnPolicy(fallbackEndOfTurnDelay: fallbackDelay)
    }
}

/// 沉浸式实时语音页：持续双工、可插话、流式字幕和单次自动重连均由统一会话状态驱动。
struct RealtimeConversationView: View {
    @State private var coordinator: RealtimeConversationCoordinator
    @State private var captionsVisible = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onSpeechPlayback: () -> Void
    private let onRequestAccess: () -> Void

    init(
        chat: ChatViewModel,
        deps: ChatDependencies,
        onSpeechPlayback: @escaping () -> Void,
        onRequestAccess: @escaping () -> Void
    ) {
        _coordinator = State(
            initialValue: RealtimeConversationCoordinator(chat: chat, deps: deps)
        )
        self.onSpeechPlayback = onSpeechPlayback
        self.onRequestAccess = onRequestAccess
    }

    private var session: RealtimeVoiceSession { coordinator.session }
    private var character: CharacterDTO { coordinator.chat.character }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                livePresence
                Spacer(minLength: 18)
                subtitleArea
                Spacer(minLength: 18)
                controls
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 18)

            if session.phase == .failed {
                failureCard
            }
        }
        .preferredColorScheme(.dark)
        .task { await coordinator.start() }
        .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { note in
            guard note.object as? UUID == character.id else { return }
            Task { await coordinator.chat.refreshCharacter() }
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
        .onChange(of: session.phase) { oldValue, newValue in
            if newValue == .speaking, oldValue != .speaking {
                onSpeechPlayback()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
        ) { handleAudioInterruption($0) }
        .onDisappear { Task { await coordinator.stop() } }
        .alert("语音用量", isPresented: Binding(get: { coordinator.accessError != nil }, set: { if !$0 { coordinator.accessError = nil } })) {
            Button("查看用量与权益") { onRequestAccess(); endConversation() }
            Button("结束", role: .cancel) { endConversation() }
        } message: { Text(coordinator.accessError ?? "") }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.065)
            RadialGradient(
                colors: [phaseTint.opacity(0.24), .clear],
                center: .init(x: 0.5, y: 0.34),
                startRadius: 8,
                endRadius: 390
            )
            Circle()
                .fill(Color.dsQuiz.opacity(0.11))
                .frame(width: 330, height: 330)
                .blur(radius: 90)
                .offset(x: 170, y: 350)
            Circle()
                .fill(Color.dsCyan.opacity(0.09))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: -180, y: -360)
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: session.phase)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                endConversation()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("结束实时语音")

            Spacer()

            VStack(spacing: 3) {
                Text(character.card.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionTint)
                        .frame(width: 6, height: 6)
                    Text(connectionLabel)
                    if session.elapsedSeconds > 0 {
                        Text("·")
                        Text(durationText)
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var livePresence: some View {
        VStack(spacing: 26) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(
                            phaseTint.opacity(0.3 - Double(index) * 0.07),
                            lineWidth: 1.5
                        )
                        .frame(
                            width: 188 + CGFloat(index * 34),
                            height: 188 + CGFloat(index * 34)
                        )
                        .scaleEffect(
                            reduceMotion
                                ? 1
                                : 1 + session.activityLevel * (0.025 + Double(index) * 0.012)
                        )
                        .opacity(session.isMuted ? 0.25 : 1)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.18),
                                phaseTint.opacity(0.42),
                                phaseTint.opacity(0.1),
                            ],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: 112
                        )
                    )
                    .frame(width: 168, height: 168)
                    .overlay {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 1)
                    }
                    .shadow(color: phaseTint.opacity(0.42), radius: 34)
                    .scaleEffect(reduceMotion ? 1 : 1 + session.activityLevel * 0.055)

                AvatarBadge(
                    name: character.card.name, tint: .white, size: 104,
                    imageName: character.card.avatarAssetName,
                    remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                    usesPendingPlaceholder: true
                )
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.09),
                value: session.activityLevel
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(character.card.name)，\(statusTitle)")

            VStack(spacing: 7) {
                Text(statusTitle)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
            .animation(reduceMotion ? nil : DSAnimation.snappy, value: session.phase)
        }
    }

    @ViewBuilder
    private var subtitleArea: some View {
        if captionsVisible {
            VStack(spacing: 12) {
                if !displayedUserText.isEmpty {
                    subtitle(
                        speaker: "你",
                        text: displayedUserText,
                        alignment: .trailing,
                        tint: .dsCyan
                    )
                }
                if !session.assistantTranscript.isEmpty {
                    subtitle(
                        speaker: character.card.name,
                        text: session.assistantTranscript,
                        alignment: .leading,
                        tint: phaseTint
                    )
                }
                if displayedUserText.isEmpty && session.assistantTranscript.isEmpty {
                    Text("字幕会在这里实时出现")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.34))
                        .frame(maxWidth: .infinity, minHeight: 74)
                }
            }
            .frame(maxWidth: 560)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Text("字幕已隐藏")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
                .frame(height: 74)
        }
    }

    private func subtitle(
        speaker: String,
        text: String,
        alignment: Alignment,
        tint: Color
    ) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 4) {
            Text(speaker)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .contentTransition(.opacity)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        VStack(spacing: 18) {
            Text("原始音频仅在本机识别；只有终稿文本会发送给 AI")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.38))
                .multilineTextAlignment(.center)

            HStack(spacing: 30) {
                controlButton(
                    icon: captionsVisible ? "captions.bubble.fill" : "captions.bubble",
                    label: captionsVisible ? "字幕" : "显示字幕",
                    selected: captionsVisible
                ) {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                        captionsVisible.toggle()
                    }
                }

                Button {
                    endConversation()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 70)
                        .background(Color.dsBrandCoral, in: Circle())
                        .shadow(color: Color.dsBrandCoral.opacity(0.36), radius: 18, y: 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("结束实时语音")

                controlButton(
                    icon: session.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: session.isMuted ? "打开麦克风" : "静音",
                    selected: session.isMuted
                ) {
                    Haptics.selection()
                    session.toggleMuted()
                }
                .disabled(session.phase == .connecting || session.phase == .failed)
            }
        }
    }

    private func controlButton(
        icon: String,
        label: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.title3.weight(.medium))
                    .frame(width: 54, height: 54)
                    .background(
                        selected ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.ultraThinMaterial),
                        in: Circle()
                    )
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var failureCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(Color.dsBrandCoral)
            VStack(spacing: 6) {
                Text("实时语音暂时不可用")
                    .font(.headline)
                Text(session.errorMessage ?? "请检查麦克风或音频设备后重试。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("结束") { endConversation() }
                    .buttonStyle(.bordered)
                if session.requiresSettings {
                    Button("打开设置") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("重试") { Task { await session.start() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 28, y: 12)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var displayedUserText: String {
        session.liveTranscript.isEmpty ? session.userTranscript : session.liveTranscript
    }

    private var phaseTint: Color {
        switch session.phase {
        case .userSpeaking: .dsCyan
        case .thinking, .connecting, .reconnecting: .dsQuiz
        case .speaking: .dsSky
        case .failed: .dsBrandCoral
        case .idle, .listening, .paused: .dsSkyDeep
        }
    }

    private var connectionTint: Color {
        switch session.phase {
        case .failed: .dsDanger
        case .connecting, .reconnecting: .dsWarning
        case .idle, .paused: .white.opacity(0.35)
        default: .dsSuccess
        }
    }

    private var connectionLabel: String {
        switch session.phase {
        case .connecting: "准备端侧模型"
        case .reconnecting: "正在恢复"
        case .failed: "已断开"
        case .paused: "已暂停"
        case .idle: "已结束"
        default: "端侧实时"
        }
    }

    private var statusTitle: String {
        if session.isMuted { return "麦克风已关闭" }
        return switch session.phase {
        case .idle: "对话已结束"
        case .connecting: "正在准备端侧语音"
        case .listening: "我在听"
        case .userSpeaking: "正在听你说"
        case .thinking: "\(character.card.name) 正在回应"
        case .speaking: "\(character.card.name) 正在说"
        case .reconnecting: "正在恢复对话"
        case .paused: "对话已暂停"
        case .failed: "实时语音已中断"
        }
    }

    private var statusDetail: String {
        if session.isMuted { return "点按麦克风即可继续" }
        return switch session.phase {
        case .idle: "字幕已保存到聊天记录"
        case .connecting: "正在启动 Apple 系统识别"
        case .listening: "自然说英语，不需要按住按钮"
        case .userSpeaking: "说完后会自动接话"
        case .thinking: "你随时可以继续开口"
        case .speaking: "直接说话就能自然插话"
        case .reconnecting: "正在保留当前字幕与上下文"
        case .paused: "回到应用后会自动恢复"
        case .failed: "可立即重试"
        }
    }

    private var durationText: String {
        let minutes = session.elapsedSeconds / 60
        let seconds = session.elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func endConversation() {
        Haptics.impact(.medium)
        Task {
            await coordinator.stop()
            dismiss()
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }
        switch type {
        case .began:
            Task { await session.suspend() }
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                .contains(.shouldResume)
            if shouldResume {
                Task { await session.resume() }
            }
        @unknown default:
            break
        }
    }
}
