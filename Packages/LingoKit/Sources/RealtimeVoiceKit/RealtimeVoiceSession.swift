import CoreKit
import Foundation
import Observation

/// 客户端实时语音总状态机：端上识别 → 文本流 → 端上播报，并支持自然插话。
@MainActor
@Observable
public final class RealtimeVoiceSession {
    public private(set) var phase: RealtimeVoicePhase = .idle
    public private(set) var inputLevel: Double = 0
    public private(set) var liveTranscript = ""
    public private(set) var userTranscript = ""
    public private(set) var assistantTranscript = ""
    public private(set) var isMuted = false
    public private(set) var errorMessage: String?
    public private(set) var requiresSettings = false

    private let input: any RealtimeSpeechInput
    private let output: any RealtimeSpeechOutput
    private let conversation: RealtimeVoiceConversationClient
    private let localeIdentifier: String
    private let voiceLanguage: String
    private let contextualStrings: [String]
    private var turnDetector: ClientVoiceTurnDetector

    private var lifecycleGeneration = UUID()
    private var activeResponseID: UUID?
    private var responseTask: Task<Void, Never>?
    private var pendingTurnTask: Task<Void, Never>?
    private var pendingAssistantSave: Task<Void, Never>?
    private var userSpeechActive = false
    private var preSpeechTranscript = ""
    private var transcriptBaseline = ""

    public convenience init(
        audioSession: AudioSessionCoordinator,
        conversation: RealtimeVoiceConversationClient,
        localeIdentifier: String = "en-US",
        voiceLanguage: String = "en-US",
        contextualStrings: [String] = [],
        turnPolicy: VoiceTurnDetectionPolicy = .init()
    ) {
        self.init(
            input: AppleRealtimeSpeechRecognizer(audioSession: audioSession),
            output: AppleRealtimeSpeechSynthesizer(),
            conversation: conversation,
            localeIdentifier: localeIdentifier,
            voiceLanguage: voiceLanguage,
            contextualStrings: contextualStrings,
            turnPolicy: turnPolicy
        )
    }

    init(
        input: any RealtimeSpeechInput,
        output: any RealtimeSpeechOutput,
        conversation: RealtimeVoiceConversationClient,
        localeIdentifier: String,
        voiceLanguage: String,
        contextualStrings: [String],
        turnPolicy: VoiceTurnDetectionPolicy
    ) {
        self.input = input
        self.output = output
        self.conversation = conversation
        self.localeIdentifier = localeIdentifier
        self.voiceLanguage = voiceLanguage
        self.contextualStrings = contextualStrings
        self.turnDetector = ClientVoiceTurnDetector(policy: turnPolicy)

        input.onLevel = { [weak self] level, timestamp in
            self?.receiveLevel(level, at: timestamp)
        }
        input.onTranscript = { [weak self] transcript in
            self?.receiveTranscript(transcript)
        }
        input.onFailure = { [weak self] _ in
            guard let self, self.phase != .idle, self.phase != .paused else { return }
            self.errorMessage = "刚才没有听清，我已经重新开始聆听。"
            self.input.restartRecognition()
        }
    }

    public func start() async {
        guard phase == .idle || phase == .paused || phase == .failed else { return }
        let generation = UUID()
        lifecycleGeneration = generation
        phase = .connecting
        errorMessage = nil
        requiresSettings = false

        do {
            try await input.start(
                localeIdentifier: localeIdentifier,
                contextualStrings: contextualStrings
            )
            guard lifecycleGeneration == generation else {
                await input.stop()
                return
            }
            resetInputTurn()
            input.setMuted(isMuted)
            phase = .listening
        } catch {
            guard lifecycleGeneration == generation else { return }
            let voiceError = error as? RealtimeVoiceError
            errorMessage = voiceError?.localizedDescription ?? error.localizedDescription
            requiresSettings = voiceError?.requiresSettings == true
            phase = .failed
        }
    }

    public func stop() async {
        lifecycleGeneration = UUID()
        pendingTurnTask?.cancel()
        pendingTurnTask = nil
        interruptActiveResponse(nextPhase: .idle)
        await pendingAssistantSave?.value
        await input.stop()
        resetInputTurn()
        isMuted = false
        phase = .idle
    }

    /// 进入后台时保留页面，只暂停正在占用的麦克风和回复；回前台可原地恢复。
    public func suspend() async {
        guard phase != .idle, phase != .paused, phase != .failed else { return }
        lifecycleGeneration = UUID()
        pendingTurnTask?.cancel()
        pendingTurnTask = nil
        interruptActiveResponse(nextPhase: .paused)
        await pendingAssistantSave?.value
        await input.stop()
        inputLevel = 0
        phase = .paused
    }

    public func resume() async {
        guard phase == .paused else { return }
        await start()
    }

    public func toggleMuted() {
        isMuted.toggle()
        turnDetector.reset()
        userSpeechActive = false
        liveTranscript = ""
        inputLevel = 0
        input.setMuted(isMuted)
    }

    #if DEBUG
    /// 模拟器没有稳定麦克风输入时，用于验证 AI → 分句 → TTS → 落库全链路。
    public func submitDebugTurn(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        userTranscript = text
        liveTranscript = ""
        beginResponse(to: text)
    }
    #endif

    private var agentIsBusy: Bool {
        activeResponseID != nil || responseTask != nil || phase == .thinking || phase == .speaking
    }

    private func receiveLevel(_ level: Double, at timestamp: TimeInterval) {
        guard phase != .idle, phase != .connecting, phase != .failed, !isMuted else { return }
        inputLevel = level
        let events = turnDetector.ingest(
            level: level,
            at: timestamp,
            agentIsBusy: agentIsBusy
        )
        for event in events {
            switch event {
            case .speechStarted:
                pendingTurnTask?.cancel()
                pendingTurnTask = nil
                userSpeechActive = true
                transcriptBaseline = preSpeechTranscript
                errorMessage = nil
            case .interruption:
                interruptActiveResponse(nextPhase: .listening)
            case .speechEnded:
                userSpeechActive = false
                scheduleTurnFinalization()
            }
        }
    }

    private func receiveTranscript(_ transcript: String) {
        if userSpeechActive {
            liveTranscript = Self.transcript(transcript, after: transcriptBaseline)
        } else {
            preSpeechTranscript = transcript
        }
    }

    private func scheduleTurnFinalization() {
        pendingTurnTask?.cancel()
        pendingTurnTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self else { return }
            self.finalizeUserTurn()
        }
    }

    private func finalizeUserTurn() {
        let text = Self.transcript(input.latestTranscript, after: transcriptBaseline)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        input.restartRecognition()
        resetInputTurn()
        guard !text.isEmpty else {
            errorMessage = "没听清这句话，请再说一次。"
            if phase != .speaking, phase != .thinking {
                phase = .listening
            }
            return
        }

        userTranscript = text
        beginResponse(to: text)
    }

    private func beginResponse(to userText: String) {
        guard !userText.isEmpty else { return }
        if agentIsBusy {
            interruptActiveResponse(nextPhase: .listening)
        }

        let responseID = UUID()
        activeResponseID = responseID
        phase = .thinking
        assistantTranscript = ""
        errorMessage = nil
        // 在请求发出前就清空上一轮播报进度；否则“思考中”被打断时会误存上一轮文本。
        output.beginResponse(language: voiceLanguage)
        let pendingSave = pendingAssistantSave
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
        queueAssistantSave(spokenText)
    }

    private func interruptActiveResponse(nextPhase: RealtimeVoicePhase) {
        guard activeResponseID != nil || responseTask != nil else {
            phase = nextPhase
            return
        }
        activeResponseID = nil
        responseTask?.cancel()
        responseTask = nil
        let heard = SpokenTextSanitizer.sanitize(output.stop())
        assistantTranscript = heard
        if !heard.isEmpty {
            queueAssistantSave(heard)
        }
        phase = nextPhase
    }

    private func queueAssistantSave(_ text: String) {
        guard !text.isEmpty else { return }
        let previous = pendingAssistantSave
        let conversation = conversation
        pendingAssistantSave = Task {
            await previous?.value
            await conversation.saveAssistant(text)
        }
    }

    private func resetInputTurn() {
        turnDetector.reset()
        userSpeechActive = false
        preSpeechTranscript = ""
        transcriptBaseline = ""
        liveTranscript = ""
    }

    static func transcript(_ current: String, after baseline: String) -> String {
        let current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseline = baseline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseline.isEmpty,
              current.lowercased().hasPrefix(baseline.lowercased()) else {
            return current
        }
        return String(current.dropFirst(baseline.count))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
