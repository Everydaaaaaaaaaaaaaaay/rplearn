import CoreKit
import Foundation
import Observation
import SpeechKit

/// 低成本实时语音编排器：Apple ASR → 现有流式 LLM → 端侧流式 TTS。
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
    public private(set) var errorMessage: String?
    public private(set) var requiresSettings = false
    public private(set) var isMuted = false
    public private(set) var isEnding = false

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
    private var finalizationID: UUID?
    private var interruptionTask: Task<Void, Never>?
    private var lastVoiceAt: ContinuousClock.Instant?
    private var inputTurnStartedAt: ContinuousClock.Instant?
    private var lastTranscriptProgressAt: ContinuousClock.Instant?
    private var longestTranscriptWords = 0
    private var longestTranscriptCharacters = 0
    private var endpointRequested = false
    private let clock = ContinuousClock()

    public init(
        audioSession: AudioSessionCoordinator,
        speech: any SpeechService,
        conversation: RealtimeVoiceConversationClient,
        voiceLanguage: String = "en-US",
        voiceHint: SpeechVoiceHint? = nil,
        turnPolicy: VoiceTurnPolicy = .init()
    ) {
        self.input = AppleRealtimeSpeechRecognizer(
            audioSession: audioSession,
            localeIdentifier: voiceLanguage
        )
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
        finalizationID = nil
        resetInputTurn()

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
        phase = .idle
        await interruptActiveResponse(nextPhase: .idle)
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
        phase = .paused
        await interruptActiveResponse(nextPhase: .paused)
        await input.stop()
        resetInputTurn()
        rawInputLevel = 0
        activityLevel = 0
        phase = .paused
    }

    public func resume() async {
        guard phase == .paused else { return }
        await start()
    }

    /// A lease/credit failure must not cut off a reply already admitted by the server.
    public func finishSpeakingAndStop() async {
        isEnding = true
        isMuted = true
        input.setMuted(true)
        endpointFallbackTask?.cancel()
        endpointFallbackTask = nil
        liveTranscript = ""
        errorMessage = "本轮回复结束后，通话将结束。"
        while activeResponseID != nil || finalizationID != nil {
            if let responseTask {
                await responseTask.value
            } else {
                // A response may still be preparing its output before installing its task.
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        await stop()
    }

    public func toggleMuted() {
        guard !isEnding, phase != .idle, phase != .paused, phase != .failed else { return }
        isMuted.toggle()
        endpointFallbackTask?.cancel()
        endpointFallbackTask = nil
        resetInputTurn()
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
        output.onPlaybackStarted = { [weak self] in
            guard let self, self.activeResponseID != nil, self.phase == .thinking else { return }
            self.phase = .speaking
        }
        input.onLevel = { [weak self] level in self?.receiveLevel(level) }
        input.onSpeechStarted = { [weak self] in self?.receiveSpeechStarted() }
        input.onTranscription = { [weak self] transcription in
            self?.receiveTranscription(transcription)
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
        // Input levels are already speech-gated; quiet speech must keep the turn open too.
        if level > 0 { lastVoiceAt = clock.now }
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
        if inputTurnStartedAt == nil { inputTurnStartedAt = clock.now }
        lastVoiceAt = clock.now
        let wasBusy = agentIsBusy
        phase = .userSpeaking

        if wasBusy {
            // Invalidate the reply synchronously; late deltas cannot enqueue more speech.
            beginInterruption(nextPhase: .userSpeaking)
        }
        if !endpointRequested { scheduleEndpointFallback() }
    }

    private func receiveTranscription(_ transcription: RealtimeTranscription) {
        guard phase != .idle, phase != .connecting, phase != .paused, phase != .failed,
              !isMuted else { return }
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if transcription.isFinal, activeResponseID == nil,
               endpointRequested || phase == .userSpeaking {
                resetInputTurn()
                phase = .listening
            }
            return
        }
        errorMessage = nil

        if transcription.isFinal {
            endpointFallbackTask?.cancel()
            endpointFallbackTask = nil
            let generation = generation
            Task { [weak self] in
                guard let self, self.generation == generation, !self.isMuted,
                      self.phase != .idle, self.phase != .paused, self.phase != .failed else { return }
                await self.submitFinalTranscript(text)
            }
        } else {
            let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            let characters = words.reduce(0) { $0 + $1.count }
            // Case/punctuation churn and ASR revisions are not new speech. Track
            // a high-water mark so alternating hypotheses cannot reset the cap.
            if words.count > longestTranscriptWords || characters > longestTranscriptCharacters {
                lastTranscriptProgressAt = clock.now
                longestTranscriptWords = max(longestTranscriptWords, words.count)
                longestTranscriptCharacters = max(longestTranscriptCharacters, characters)
            }
            if inputTurnStartedAt == nil { inputTurnStartedAt = clock.now }
            liveTranscript = text
            if agentIsBusy { beginInterruption(nextPhase: .userSpeaking) }
            phase = .userSpeaking
            if !endpointRequested, endpointFallbackTask == nil { scheduleEndpointFallback() }
        }
    }

    private func scheduleEndpointFallback() {
        endpointFallbackTask?.cancel()
        endpointFallbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    guard let startedAt = self.inputTurnStartedAt else { return }
                    let progressAt = self.lastTranscriptProgressAt ?? startedAt
                    let silenceAt = max(self.lastVoiceAt ?? startedAt, progressAt)
                        .advanced(by: self.turnPolicy.fallbackEndOfTurnDelay)
                    // Acoustic activity may extend a normal pause, but never
                    // indefinitely when recognition has stopped making progress.
                    let stalledAt = progressAt.advanced(by: max(self.turnPolicy.fallbackEndOfTurnDelay,
                                                               self.turnPolicy.maximumTranscriptStall))
                    let remaining = self.clock.now.duration(to: min(silenceAt, stalledAt))
                    if remaining <= .zero { break }
                    try await Task.sleep(for: remaining)
                }
            } catch {
                return
            }
            guard !Task.isCancelled, !self.endpointRequested else { return }
            self.endpointRequested = true
            if !self.liveTranscript.isEmpty { self.phase = .thinking }
            await self.input.finishCurrentTurn()
        }
    }

    private func submitFinalTranscript(_ text: String) async {
        guard finalizationID == nil else { return }
        let finalizationID = UUID()
        let generation = generation
        self.finalizationID = finalizationID
        defer { if self.finalizationID == finalizationID { self.finalizationID = nil } }

        await interruptActiveResponse(nextPhase: .thinking)
        guard self.generation == generation, !isMuted else { return }
        resetInputTurn()
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
        guard activeResponseID == responseID else { return }

        let pendingSave = persistenceTail
        responseTask = Task { [weak self] in
            await pendingSave?.value
            guard !Task.isCancelled, let self, self.activeResponseID == responseID else { return }
            await self.runResponse(id: responseID, userText: userText)
        }
    }

    private func runResponse(id: UUID, userText: String) async {
        var generated = ""
        var segmenter = StreamingSpeechSegmenter()

        do {
            let stream = try await conversation.replyStream(userText, responseID: id)
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
            // An upstream cancellation can also happen without a local barge-in.
            // Release the turn so draining/ending a call cannot wait forever.
            guard activeResponseID == id else { return }
            let heard = await output.stop()
            guard activeResponseID == id else { return }
            completeResponse(id: id, spokenText: heard, interrupted: true)
        } catch {
            guard activeResponseID == id else { return }
            enqueue(segmenter.finish(), responseID: id)
            await output.waitUntilFinished()
            guard activeResponseID == id else { return }
            let heard = output.heardText
            completeResponse(id: id, spokenText: heard, interrupted: true)
            errorMessage = "回复暂时中断了，可以直接继续说。"
        }
    }

    private func enqueue(_ segments: [String], responseID: UUID) {
        guard activeResponseID == responseID else { return }
        for segment in segments where !segment.isEmpty {
            output.enqueue(segment)
        }
    }

    private func completeResponse(id: UUID, spokenText: String, interrupted: Bool = false) {
        guard activeResponseID == id else { return }
        let spokenText = SpokenTextSanitizer.sanitize(spokenText)
        activeResponseID = nil
        responseTask = nil
        assistantTranscript = spokenText
        phase = .listening
        queueAssistantSave(spokenText, interrupted: interrupted, responseID: id)
    }

    private func beginInterruption(nextPhase: RealtimeVoicePhase) {
        phase = nextPhase
        guard let responseID = activeResponseID else { return }
        activeResponseID = nil
        responseTask?.cancel()
        responseTask = nil
        let previous = interruptionTask
        let generation = generation
        interruptionTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let heard = SpokenTextSanitizer.sanitize(await self.output.stop())
            self.queueAssistantSave(heard, interrupted: true, responseID: responseID)
            if self.generation == generation { self.assistantTranscript = heard }
        }
    }

    private func interruptActiveResponse(nextPhase: RealtimeVoicePhase) async {
        beginInterruption(nextPhase: nextPhase)
        await interruptionTask?.value
    }

    private func queueAssistantSave(_ text: String, interrupted: Bool, responseID: UUID) {
        let text = SpokenTextSanitizer.sanitize(text)
        let previous = persistenceTail
        let conversation = conversation
        persistenceTail = Task {
            await previous?.value
            await conversation.saveAssistant(text, interrupted, responseID: responseID)
        }
    }

    private func startVisualClock(generation: UUID) {
        visualTask?.cancel()
        visualTask = Task { [weak self] in
            var tick = 0.0
            while !Task.isCancelled {
                guard let self, self.generation == generation else { return }
                if let startedAt = self.startedAt {
                    let seconds = Int(Date.now.timeIntervalSince(startedAt))
                    if self.elapsedSeconds != seconds { self.elapsedSeconds = seconds }
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
        resetInputTurn()
        userTranscript = ""
        assistantTranscript = ""
        activityLevel = 0
        rawInputLevel = 0
        lastVoiceAt = nil
        errorMessage = nil
        requiresSettings = false
        isEnding = false
        finalizationID = nil
    }

    private func resetInputTurn() {
        endpointFallbackTask?.cancel()
        endpointFallbackTask = nil
        liveTranscript = ""
        lastVoiceAt = nil
        inputTurnStartedAt = nil
        lastTranscriptProgressAt = nil
        longestTranscriptWords = 0
        longestTranscriptCharacters = 0
        endpointRequested = false
    }
}
