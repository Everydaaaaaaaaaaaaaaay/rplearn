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

private struct RecognitionUpdate: Sendable {
    let partial: String?
    let final: String?
}

/// FluidAudio 的双层端侧识别管线：
/// - Parakeet EOU 120M / 320ms 负责低延迟 partial 与语义端点；
/// - SenseVoice Small INT8 只在完整话轮上跑一次，负责更精确的最终文本。
private actor FluidRealtimeRecognitionEngine {
    private let converter = AudioConverter(sampleRate: 16_000)
    private var streaming: StreamingEouAsrManager?
    private var refiner: SenseVoiceManager?
    private var isPrepared = false
    private var turnSamples: [Float] = []
    private var preRollSamples: [Float] = []
    private var isCollectingTurn = false
    private var lastPartial = ""

    func prepare(
        progress: @escaping @Sendable (RealtimeModelPreparation) -> Void
    ) async throws {
        guard !isPrepared else {
            progress(.init(stage: .ready, progress: 1))
            return
        }

        let resources = try RealtimeASRModelResources.bundled()
        progress(.init(stage: .streamingRecognition, progress: 0))
        let streaming = StreamingEouAsrManager(
            chunkSize: .ms320,
            eouDebounceMs: 640
        )
        try await streaming.loadModels(from: resources.parakeetEOU320)
        progress(.init(stage: .transcriptRefinement, progress: 0.48))

        let senseVoiceModels = try SenseVoiceModels.load(
            from: resources.senseVoiceSmallINT8,
            precision: .int8
        )
        let refiner = SenseVoiceManager(models: senseVoiceModels)

        self.streaming = streaming
        self.refiner = refiner
        isPrepared = true
        progress(.init(stage: .ready, progress: 1))
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
        guard let refiner else { return fallback.isEmpty ? nil : fallback }

        let refined = normalize(try await refiner.transcribe(audio: turnSamples))
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
    private let recognitionEngine = FluidRealtimeRecognitionEngine()
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

        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let values = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            let samples = Array(values)
            let level = AudioLevelMeter.level(samples: values)
            continuation.yield(.audio(.init(
                samples: samples,
                sampleRate: format.sampleRate,
                level: level
            )))
        }

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
