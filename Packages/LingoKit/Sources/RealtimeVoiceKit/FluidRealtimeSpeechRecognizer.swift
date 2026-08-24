@preconcurrency import AVFoundation
import CoreKit
import FluidAudio
import Foundation
import SpeechKit

private struct RealtimeAudioChunk: Sendable {
    let samples: [Float]
    let sampleRate: Double
    let level: Double
}

private enum RealtimeInputCommand: Sendable {
    case audio(RealtimeAudioChunk)
    case finishTurn
    case reset
}

/// AVAudioEngine 会在自己的实时音频队列调用 tap。把闭包在主线程隔离类型之外创建，
/// 避免 Swift 6 将它错误地标记为 MainActor 闭包并在首帧音频到达时触发断言。
private func makeRealtimeAudioTap(
    continuation: AsyncStream<RealtimeInputCommand>.Continuation,
    sampleRate: Double
) -> AVAudioNodeTapBlock {
    { buffer, _ in
        guard let channel = buffer.floatChannelData?[0] else { return }
        let values = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let samples = Array(values)
        let level = AudioLevelMeter.level(samples: values)
        continuation.yield(.audio(.init(
            samples: samples,
            sampleRate: sampleRate,
            level: level
        )))
    }
}

private struct RecognitionUpdate: Sendable {
    let partial: String?
    let final: String?
}

/// FluidAudio 的双层端侧识别管线：
/// - Parakeet EOU 120M / 320ms 负责低延迟 partial 与语义端点；
/// - SenseVoice Small INT8 只在完整话轮上跑一次，负责更精确的最终文本。
private actor FluidTranscriptRefinementEngine {
    private var manager: SenseVoiceManager?

    /// SenseVoice 的同步 Core ML 初始化可能持续很久，因此让它占用独立 actor。
    /// 实时 Parakeet actor 只会在这里完全就绪后调用 transcribe。
    func prepare() throws {
        guard manager == nil else { return }
        let resources = try RealtimeASRModelResources.bundled()
        let models = try SenseVoiceModels.load(
            from: resources.senseVoiceSmallINT8,
            precision: .int8
        )
        manager = SenseVoiceManager(models: models)
    }

    func transcribe(audio: [Float]) async throws -> String? {
        guard let manager else { return nil }
        return try await manager.transcribe(audio: audio)
    }
}

private actor FluidRealtimeRecognitionEngine {
    static let shared = FluidRealtimeRecognitionEngine()

    typealias PreparationObserver = @Sendable (RealtimeModelPreparation) -> Void

    private let converter = AudioConverter(sampleRate: 16_000)
    private let transcriptRefiner = FluidTranscriptRefinementEngine()
    private var streaming: StreamingEouAsrManager?
    private var isPrepared = false
    private var isTranscriptRefinerPrepared = false
    private var preparationTask: Task<Void, Error>?
    private var preparation = RealtimeModelPreparation(
        stage: .streamingRecognition,
        progress: 0.05
    )
    private var preparationObservers: [UUID: PreparationObserver] = [:]
    private var turnSamples: [Float] = []
    private var preRollSamples: [Float] = []
    private var isCollectingTurn = false
    private var lastPartial = ""

    func prepare(
        progress: @escaping PreparationObserver
    ) async throws {
        let observerID = UUID()
        preparationObservers[observerID] = progress
        progress(preparation)
        defer { preparationObservers[observerID] = nil }

        if isPrepared { return }

        let task: Task<Void, Error>
        if let preparationTask {
            task = preparationTask
        } else {
            let newTask = Task { try await self.loadStreamingModels() }
            preparationTask = newTask
            task = newTask
        }

        do {
            try await task.value
        } catch {
            if !isPrepared { preparationTask = nil }
            throw error
        }
    }

    private func loadStreamingModels() async throws {
        let resources = try RealtimeASRModelResources.bundled()
        publishPreparation(stage: .streamingRecognition, progress: 0.05)
        let streaming = StreamingEouAsrManager(
            chunkSize: .ms320,
            eouDebounceMs: 640
        )
        try await streaming.loadModels(from: resources.parakeetEOU320)

        self.streaming = streaming
        isPrepared = true
        publishPreparation(stage: .ready, progress: 1)
    }

    func prepareTranscriptRefinement() async throws {
        guard !isTranscriptRefinerPrepared else { return }
        try await transcriptRefiner.prepare()
        isTranscriptRefinerPrepared = true
    }

    private func publishPreparation(
        stage: RealtimeModelPreparation.Stage,
        progress: Double
    ) {
        preparation = .init(stage: stage, progress: progress)
        for observer in preparationObservers.values {
            observer(preparation)
        }
    }

    func process(_ chunk: RealtimeAudioChunk) async throws -> RecognitionUpdate {
        guard let streaming else { throw RealtimeVoiceError.modelPreparationFailed }
        let samples = try converter.resample(chunk.samples, from: chunk.sampleRate)
        collectForRefinement(samples, voiceLevel: chunk.level)
        let buffer = try Self.makeBuffer(samples: samples)
        _ = try await streaming.process(audioBuffer: buffer)

        let partial = normalize(await streaming.getPartialTranscript())
        let changedPartial: String? = partial != lastPartial && !partial.isEmpty ? partial : nil
        if !partial.isEmpty { lastPartial = partial }

        if await streaming.eouDetected {
            let final = try await finalizeTurn(fallback: partial)
            return RecognitionUpdate(partial: changedPartial, final: final)
        }
        return RecognitionUpdate(partial: changedPartial, final: nil)
    }

    func finishTurn() async throws -> RecognitionUpdate {
        guard let streaming else { return .init(partial: nil, final: nil) }
        let streamed = normalize(try await streaming.finish())
        let fallback = streamed.isEmpty ? lastPartial : streamed
        let final = try await refine(fallback: fallback)
        await streaming.reset()
        resetTurnBuffers()
        return RecognitionUpdate(partial: nil, final: final)
    }

    func reset() async {
        await streaming?.reset()
        resetTurnBuffers()
    }

    private func finalizeTurn(fallback: String) async throws -> String? {
        let streamed = normalize(try await streaming?.finish() ?? fallback)
        let final = try await refine(fallback: streamed.isEmpty ? fallback : streamed)
        await streaming?.reset()
        resetTurnBuffers()
        return final
    }

    private func refine(fallback: String) async throws -> String? {
        let fallback = normalize(fallback)
        guard !turnSamples.isEmpty else { return fallback.isEmpty ? nil : fallback }
        guard isTranscriptRefinerPrepared else { return fallback.isEmpty ? nil : fallback }

        let refined = normalize(try await transcriptRefiner.transcribe(audio: turnSamples) ?? "")
        if !refined.isEmpty { return refined }
        return fallback.isEmpty ? nil : fallback
    }

    private func collectForRefinement(_ samples: [Float], voiceLevel: Double) {
        let preRollLimit = 6_400 // 400ms @ 16kHz
        if !isCollectingTurn {
            preRollSamples.append(contentsOf: samples)
            if preRollSamples.count > preRollLimit {
                preRollSamples.removeFirst(preRollSamples.count - preRollLimit)
            }
            if voiceLevel >= 0.045 {
                isCollectingTurn = true
                turnSamples = preRollSamples
                preRollSamples.removeAll(keepingCapacity: true)
            }
            return
        }
        turnSamples.append(contentsOf: samples)
    }

    private func resetTurnBuffers() {
        turnSamples.removeAll(keepingCapacity: true)
        preRollSamples.removeAll(keepingCapacity: true)
        isCollectingTurn = false
        lastPartial = ""
    }

    private func normalize(_ text: String) -> String {
        text.split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let destination = buffer.floatChannelData?[0]
        else { throw RealtimeVoiceError.audioInputUnavailable }

        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                destination.update(from: base, count: source.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}

/// App 启动后按当前设置预热端侧 ASR。通话入口与这里共享同一个加载任务和模型实例，
/// 因而即使用户在预热尚未结束时立刻拨打，也只会等待余下部分而不会重复加载。
public enum RealtimeVoiceModelPrewarmer {
    /// 首要准备只加载低延迟流式模型，通话不再等待耗时很长的精修模型。
    public static func prepareForLaunch() async {
        guard VoiceEnginePreferences.recognitionEngine() == .enhancedOnDevice else { return }
        do {
            try await FluidRealtimeRecognitionEngine.shared.prepare { _ in }
        } catch {
            Log.speech.error("端侧实时语音模型预热失败：\(error.localizedDescription)")
        }
    }

    /// 在关键的 ASR/TTS 都已可用后再加载精修模型。其独立 actor 不会阻塞
    /// Parakeet 的实时音频处理；就绪前完整话轮直接使用 Parakeet 最终稿。
    public static func prepareTranscriptRefinementForLaunch() async {
        guard VoiceEnginePreferences.recognitionEngine() == .enhancedOnDevice else { return }
        do {
            try await FluidRealtimeRecognitionEngine.shared.prepareTranscriptRefinement()
        } catch {
            Log.speech.error("SenseVoice 精修模型预热失败：\(error.localizedDescription)")
        }
    }
}

/// 麦克风始终只把 PCM 送入端侧 Core ML；Feature 层只能观察音量和文本。
/// VoiceProcessingIO 提供系统回声消除，使播放 Pocket TTS 时仍能监听用户插话。
@MainActor
public final class FluidRealtimeSpeechRecognizer: RealtimeSpeechInput {
    public var onLevel: (@MainActor @Sendable (Double) -> Void)?
    public var onSpeechStarted: (@MainActor @Sendable () -> Void)?
    public var onTranscription: (@MainActor @Sendable (RealtimeTranscription) -> Void)?
    public var onPreparation: (@MainActor @Sendable (RealtimeModelPreparation) -> Void)?
    public var onFailure: (@MainActor @Sendable (String) -> Void)?

    private let audioSession: AudioSessionCoordinator
    private let recognitionEngine = FluidRealtimeRecognitionEngine.shared
    private var audioEngine: AVAudioEngine?
    private var commandContinuation: AsyncStream<RealtimeInputCommand>.Continuation?
    private var processingTask: Task<Void, Never>?
    private var isRunning = false
    private var isMuted = false
    private var speechGateOpen = false
    private var consecutiveVoiceChunks = 0

    public init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
    }

    public func start() async throws {
        guard !isRunning else { return }
        guard await Self.requestMicrophonePermission() else {
            throw RealtimeVoiceError.microphonePermissionDenied
        }

        do {
            try await recognitionEngine.prepare { [weak self] preparation in
                Task { @MainActor [weak self] in self?.onPreparation?(preparation) }
            }
        } catch {
            Log.speech.error("端侧实时语音模型准备失败：\(error.localizedDescription)")
            await teardown()
            throw RealtimeVoiceError.modelPreparationFailed
        }

        do {
            try await audioSession.activate(.conversation)
            try startAudioEngine()
            isRunning = true
            isMuted = false
        } catch let error as RealtimeVoiceError {
            await teardown()
            throw error
        } catch {
            Log.speech.error("端侧实时语音输入启动失败：\(error.localizedDescription)")
            await teardown()
            throw RealtimeVoiceError.audioSessionFailed
        }
    }

    public func finishCurrentTurn() async {
        guard isRunning, !isMuted else { return }
        commandContinuation?.yield(.finishTurn)
    }

    public func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        consecutiveVoiceChunks = 0
        speechGateOpen = false
        if muted {
            onLevel?(0)
            commandContinuation?.yield(.reset)
        }
    }

    public func stop() async {
        await teardown()
    }

    private func startAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        #if targetEnvironment(simulator)
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            Log.speech.warning("模拟器无法启用回声消除：\(error.localizedDescription)")
        }
        #else
        try inputNode.setVoiceProcessingEnabled(true)
        #endif

        let format = inputNode.outputFormat(forBus: 0)
        guard VoiceRecorder.isRecordableInputFormat(format),
              format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved
        else { throw RealtimeVoiceError.audioInputUnavailable }

        // PCM 不能丢帧，否则 RNNT 的缓存时间轴会错位。模型在目标设备上快于实时，
        // 因此使用无界队列只用于吸收很短的调度抖动，不会持续增长。
        let (commands, continuation) = AsyncStream<RealtimeInputCommand>.makeStream(
            bufferingPolicy: .unbounded
        )
        commandContinuation = continuation
        processingTask = Task { [weak self] in
            for await command in commands {
                guard !Task.isCancelled, let self else { return }
                await self.process(command)
            }
        }

        let audioTap = makeRealtimeAudioTap(
            continuation: continuation,
            sampleRate: format.sampleRate
        )
        inputNode.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: format,
            block: audioTap
        )

        audioEngine = engine
        engine.prepare()
        try engine.start()
    }

    private func process(_ command: RealtimeInputCommand) async {
        do {
            switch command {
            case .audio(let chunk):
                guard !isMuted else { return }
                receiveLevel(chunk.level)
                let update = try await recognitionEngine.process(chunk)
                publish(update)
            case .finishTurn:
                publish(try await recognitionEngine.finishTurn())
            case .reset:
                await recognitionEngine.reset()
            }
        } catch is CancellationError {
            return
        } catch {
            Log.speech.warning("端侧实时识别中断：\(error.localizedDescription)")
            onFailure?(error.localizedDescription)
        }
    }

    private func receiveLevel(_ level: Double) {
        onLevel?(level)
        if level >= 0.07 {
            consecutiveVoiceChunks += 1
        } else if level < 0.035 {
            consecutiveVoiceChunks = 0
        }
        guard !speechGateOpen, consecutiveVoiceChunks >= 2 else { return }
        speechGateOpen = true
        onSpeechStarted?()
    }

    private func publish(_ update: RecognitionUpdate) {
        if let partial = update.partial {
            onTranscription?(.init(text: partial, isFinal: false))
        }
        if let final = update.final, !final.isEmpty {
            speechGateOpen = false
            consecutiveVoiceChunks = 0
            onTranscription?(.init(text: final, isFinal: true))
        }
    }

    private func teardown() async {
        isRunning = false
        isMuted = false
        commandContinuation?.finish()
        commandContinuation = nil
        processingTask?.cancel()
        processingTask = nil
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            try? audioEngine.inputNode.setVoiceProcessingEnabled(false)
        }
        audioEngine = nil
        speechGateOpen = false
        consecutiveVoiceChunks = 0
        await recognitionEngine.reset()
        await audioSession.deactivate()
    }

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
