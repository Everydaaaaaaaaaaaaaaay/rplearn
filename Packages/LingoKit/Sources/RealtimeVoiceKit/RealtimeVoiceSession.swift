import CoreKit
import Foundation
import Observation
import SpeechKit

/// 低成本实时语音编排器：端侧 ASR → 现有流式 LLM → 端侧流式 TTS。
/// 状态机、插话、回合端点和持久化只在这里协调，模型实现均位于协议后方。
@MainActor
@Observable
public final class RealtimeVoiceSession {
    public private(set) var phase: RealtimeVoicePhase = .idle
    public private(set) var liveTranscript = ""
    public private(set) var userTranscript = ""
    public private(set) var assistantTranscript = ""
    public private(set) var activityLevel = 0.0
    public private(set) var elapsedSeconds = 0
    public private(set) var preparation: RealtimeModelPreparation?
    public private(set) var errorMessage: String?
    public private(set) var requiresSettings = false
    public private(set) var isMuted = false

    private let input: any RealtimeSpeechInput
    private let output: any RealtimeSpeechOutput
    private let conversation: RealtimeVoiceConversationClient
    private let voiceLanguage: String
    private let voiceHint: SpeechVoiceHint?
    private let turnPolicy: VoiceTurnPolicy

    private var generation = UUID()
    private var startedAt: Date?
    private var rawInputLevel = 0.0
    private var activeResponseID: UUID?
    private var responseTask: Task<Void, Never>?
    private var endpointFallbackTask: Task<Void, Never>?
    private var visualTask: Task<Void, Never>?
    private var persistenceTail: Task<Void, Never>?
    private var finalizationInProgress = false

    public init(
        audioSession: AudioSessionCoordinator,
        speech: any SpeechService,
        conversation: RealtimeVoiceConversationClient,
        voiceLanguage: String = "en-US",
        voiceHint: SpeechVoiceHint? = nil,
        turnPolicy: VoiceTurnPolicy = .init()
    ) {
        switch VoiceEnginePreferences.recognitionEngine() {
        case .system:
            self.input = AppleRealtimeSpeechRecognizer(
                audioSession: audioSession,
                localeIdentifier: voiceLanguage
            )
        case .enhancedOnDevice:
            self.input = FluidRealtimeSpeechRecognizer(audioSession: audioSession)
        }
        self.output = AdaptiveRealtimeSpeechOutput(speech: speech)
        self.conversation = conversation
        self.voiceLanguage = voiceLanguage
        self.voiceHint = voiceHint
        self.turnPolicy = turnPolicy
        bindInput()
    }

    /// 测试或替代端侧引擎时使用的依赖注入入口。
    public init(
        input: any RealtimeSpeechInput,
        output: any RealtimeSpeechOutput,
        conversation: RealtimeVoiceConversationClient,
        voiceLanguage: String = "en-US",
        voiceHint: SpeechVoiceHint? = nil,
        turnPolicy: VoiceTurnPolicy = .init()
    ) {
        self.input = input
        self.output = output
        self.conversation = conversation
        self.voiceLanguage = voiceLanguage
        self.voiceHint = voiceHint
        self.turnPolicy = turnPolicy
        bindInput()
    }

    public func start() async {
        guard phase == .idle || phase == .paused || phase == .failed else { return }
        generation = UUID()
        let currentGeneration = generation
        phase = .connecting
        errorMessage = nil
        requiresSettings = false
        finalizationInProgress = false
        preparation = nil

        do {
            try await input.start()
            guard generation == currentGeneration else {
                await input.stop()
                return
            }
            isMuted = false
            input.setMuted(false)
            startedAt = startedAt ?? .now
            phase = .listening
            startVisualClock(generation: currentGeneration)
        } catch {
            guard generation == currentGeneration else { return }
            await fail(error)
        }
    }

    public func stop() async {
        generation = UUID()
        endpointFallbackTask?.cancel()
        endpointFallbackTask = nil
        visualTask?.cancel()
        visualTask = nil
        let hadActiveResponse = activeResponseID != nil || responseTask != nil
        responseTask?.cancel()
        responseTask = nil
        activeResponseID = nil

        let heard = SpokenTextSanitizer.sanitize(await output.stop())
        if hadActiveResponse, !heard.isEmpty {
            queueAssistantSave(heard, interrupted: true)
        }
        await input.stop()
        await persistenceTail?.value
        resetTransientState()
        startedAt = nil
        elapsedSeconds = 0
        isMuted = false
        phase = .idle
    }

    public func suspend() async {
        guard phase != .idle, phase != .paused, phase != .failed else { return }
        generation = UUID()
        endpointFallbackTask?.cancel()
        endpointFallbackTask = nil
        visualTask?.cancel()
        visualTask = nil
        let hadActiveResponse = activeResponseID != nil || responseTask != nil
        responseTask?.cancel()
        responseTask = nil
        activeResponseID = nil
        let heard = SpokenTextSanitizer.sanitize(await output.stop())
        if hadActiveResponse, !heard.isEmpty {
            queueAssistantSave(heard, interrupted: true)
        }
        await input.stop()
        rawInputLevel = 0
        activityLevel = 0
        phase = .paused
    }

    public func resume() async {
        guard phase == .paused else { return }
        await start()
    }

    public func toggleMuted() {
        isMuted.toggle()
        endpointFallbackTask?.cancel()
        endpointFallbackTask = nil
        liveTranscript = ""
        rawInputLevel = 0
        activityLevel = 0
        input.setMuted(isMuted)
        if !isMuted, phase != .speaking, phase != .thinking {
            phase = .listening
        }
    }

    #if DEBUG
    public func submitDebugTurn(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await submitFinalTranscript(text) }
    }
    #endif

    private func bindInput() {
        input.onLevel = { [weak self] level in self?.receiveLevel(level) }
        input.onSpeechStarted = { [weak self] in self?.receiveSpeechStarted() }
        input.onTranscription = { [weak self] transcription in
            self?.receiveTranscription(transcription)
        }
        input.onPreparation = { [weak self] preparation in
            self?.preparation = preparation
        }
        input.onFailure = { [weak self] failure in
            guard let self, self.phase != .idle, self.phase != .paused else { return }
            self.errorMessage = "语音识别刚刚中断，正在恢复：\(failure)"
        }
    }

    private var agentIsBusy: Bool {
        activeResponseID != nil || responseTask != nil || phase == .thinking || phase == .speaking
    }

    private func receiveLevel(_ level: Double) {
        guard phase != .idle, phase != .connecting, phase != .paused, phase != .failed,
              !isMuted else { return }
        rawInputLevel = level
        if phase == .listening || phase == .userSpeaking {
            activityLevel = level
        }
    }

    private func receiveSpeechStarted() {
        guard phase != .idle, phase != .connecting, phase != .paused, phase != .failed,
              !isMuted else { return }
        endpointFallbackTask?.cancel()
        endpointFallbackTask = nil
        liveTranscript = ""
        phase = .userSpeaking

        if agentIsBusy {
            Task { [weak self] in
                await self?.interruptActiveResponse(nextPhase: .userSpeaking)
            }
        }
    }

    private func receiveTranscription(_ transcription: RealtimeTranscription) {
        guard phase != .idle, phase != .connecting, phase != .paused, phase != .failed,
              !isMuted else { return }
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = nil

        if transcription.isFinal {
            endpointFallbackTask?.cancel()
            endpointFallbackTask = nil
            Task { [weak self] in await self?.submitFinalTranscript(text) }
        } else {
            liveTranscript = text
            phase = .userSpeaking
            scheduleEndpointFallback(for: text)
        }
    }

    private func scheduleEndpointFallback(for transcript: String) {
        endpointFallbackTask?.cancel()
        endpointFallbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.turnPolicy.fallbackEndOfTurnDelay)
            } catch {
                return
            }
            guard !Task.isCancelled, self.liveTranscript == transcript else { return }
            self.phase = .thinking
            await self.input.finishCurrentTurn()
        }
    }

    private func submitFinalTranscript(_ text: String) async {
        guard !finalizationInProgress else { return }
        finalizationInProgress = true
        defer { finalizationInProgress = false }

        if agentIsBusy {
            await interruptActiveResponse(nextPhase: .thinking)
        }
        liveTranscript = ""
        userTranscript = text
        await beginResponse(to: text)
    }

    private func beginResponse(to userText: String) async {
        let responseID = UUID()
        activeResponseID = responseID
        assistantTranscript = ""
        errorMessage = nil
        phase = .thinking
        await output.beginResponse(language: voiceLanguage, voiceHint: voiceHint)

        let pendingSave = persistenceTail
        responseTask = Task { [weak self] in
            await pendingSave?.value
            guard !Task.isCancelled, let self, self.activeResponseID == responseID else { return }
            await self.runResponse(id: responseID, userText: userText)
        }
    }

    private func runResponse(id: UUID, userText: String) async {
        var generated = ""
        var segmenter = StreamingSpeechSegmenter(maximumWordsWithoutPunctuation: 7)

        do {
            let stream = try await conversation.replyStream(userText)
            try Task.checkCancellation()
            guard activeResponseID == id else { return }

            for try await delta in stream {
                try Task.checkCancellation()
                guard activeResponseID == id else { return }
                generated += delta
                assistantTranscript = SpokenTextSanitizer.sanitize(generated)
                enqueue(segmenter.append(delta), responseID: id)
            }
            enqueue(segmenter.finish(), responseID: id)
            try Task.checkCancellation()

            guard !assistantTranscript.isEmpty else {
                throw RealtimeVoiceError.emptyAIResponse
            }
            await output.waitUntilFinished()
            try Task.checkCancellation()
            guard activeResponseID == id else { return }
            completeResponse(id: id, spokenText: output.heardText)
        } catch is CancellationError {
            return
        } catch {
            guard activeResponseID == id else { return }
            enqueue(segmenter.finish(), responseID: id)
            await output.waitUntilFinished()
            guard activeResponseID == id else { return }
            let heard = output.heardText
            if !heard.isEmpty {
                completeResponse(id: id, spokenText: heard)
            } else {
                activeResponseID = nil
                responseTask = nil
                phase = .listening
            }
            errorMessage = "回复暂时中断了，可以直接继续说。"
        }
    }

    private func enqueue(_ segments: [String], responseID: UUID) {
        guard activeResponseID == responseID else { return }
        for segment in segments where !segment.isEmpty {
            output.enqueue(segment)
            phase = .speaking
        }
    }

    private func completeResponse(id: UUID, spokenText: String) {
        guard activeResponseID == id else { return }
        let spokenText = SpokenTextSanitizer.sanitize(spokenText)
        activeResponseID = nil
        responseTask = nil
        assistantTranscript = spokenText
        phase = .listening
        if !spokenText.isEmpty { queueAssistantSave(spokenText, interrupted: false) }
    }

    private func interruptActiveResponse(nextPhase: RealtimeVoicePhase) async {
        guard activeResponseID != nil || responseTask != nil else {
            phase = nextPhase
            return
        }
        activeResponseID = nil
        responseTask?.cancel()
        responseTask = nil
        let heard = SpokenTextSanitizer.sanitize(await output.stop())
        assistantTranscript = heard
        if !heard.isEmpty { queueAssistantSave(heard, interrupted: true) }
        phase = nextPhase
    }

    private func queueAssistantSave(_ text: String, interrupted: Bool) {
        let text = SpokenTextSanitizer.sanitize(text)
        guard !text.isEmpty else { return }
        let previous = persistenceTail
        let conversation = conversation
        persistenceTail = Task {
            await previous?.value
            await conversation.saveAssistant(text, interrupted)
        }
    }

    private func startVisualClock(generation: UUID) {
        visualTask?.cancel()
        visualTask = Task { [weak self] in
            var tick = 0.0
            while !Task.isCancelled {
                guard let self, self.generation == generation else { return }
                if let startedAt = self.startedAt {
                    self.elapsedSeconds = Int(Date.now.timeIntervalSince(startedAt))
                }
                tick += 0.42
                if self.phase == .speaking {
                    self.activityLevel = 0.62 + sin(tick) * 0.16
                } else if self.phase == .thinking {
                    self.activityLevel = 0.22 + sin(tick) * 0.06
                } else if self.phase == .listening {
                    self.activityLevel = max(self.rawInputLevel, 0.08)
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func fail(_ error: Error) async {
        generation = UUID()
        endpointFallbackTask?.cancel()
        endpointFallbackTask = nil
        visualTask?.cancel()
        visualTask = nil
        responseTask?.cancel()
        responseTask = nil
        activeResponseID = nil
        _ = await output.stop()
        await input.stop()
        activityLevel = 0
        let realtimeError = error as? RealtimeVoiceError
        errorMessage = realtimeError?.localizedDescription ?? error.localizedDescription
        requiresSettings = realtimeError?.requiresSettings == true
        phase = .failed
    }

    private func resetTransientState() {
        liveTranscript = ""
        userTranscript = ""
        assistantTranscript = ""
        activityLevel = 0
        rawInputLevel = 0
        preparation = nil
        errorMessage = nil
        requiresSettings = false
        finalizationInProgress = false
    }
}
