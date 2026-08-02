import AVFoundation
import CoreKit
import Foundation
import Speech
import SpeechKit

private final class RealtimeAudioInputRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var lastLevelReport: TimeInterval = 0
    private let reportLevel: @Sendable (Double, TimeInterval) -> Void

    init(reportLevel: @escaping @Sendable (Double, TimeInterval) -> Void) {
        self.reportLevel = reportLevel
    }

    func replaceRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelReport >= 0.05,
              let channel = buffer.floatChannelData?.pointee else { return }
        lastLevelReport = now
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        reportLevel(AudioLevelMeter.level(samples: samples), now)
    }
}

/// Apple Speech 的持续输入实现。音频始终留在端上，只向外发布文本和音量。
@MainActor
public final class AppleRealtimeSpeechRecognizer: RealtimeSpeechInput {
    public private(set) var latestTranscript = ""
    public var onLevel: (@MainActor @Sendable (Double, TimeInterval) -> Void)?
    public var onTranscript: (@MainActor @Sendable (String) -> Void)?
    public var onFailure: (@MainActor @Sendable (String) -> Void)?

    private let audioSession: AudioSessionCoordinator
    private var recognizer: SFSpeechRecognizer?
    private var engine: AVAudioEngine?
    private var runtime: RealtimeAudioInputRuntime?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionGeneration = UUID()
    private var isRunning = false
    private var isMuted = false
    private var contextualStrings: [String] = []
    private var prefersOnDeviceRecognition = true
    private var activeRequestUsesOnDeviceRecognition = false

    public init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
    }

    public func start(localeIdentifier: String, contextualStrings: [String]) async throws {
        guard !isRunning else { return }
        guard await Self.requestMicrophonePermission() else {
            throw RealtimeVoiceError.microphonePermissionDenied
        }
        guard await Self.requestSpeechAuthorization() else {
            throw RealtimeVoiceError.speechRecognitionPermissionDenied
        }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        guard let recognizer, recognizer.isAvailable else {
            throw RealtimeVoiceError.speechRecognizerUnavailable
        }

        do {
            try await audioSession.activate(.conversation)
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode

            #if targetEnvironment(simulator)
            do {
                try inputNode.setVoiceProcessingEnabled(true)
            } catch {
                // 模拟器并不总提供 VoiceProcessingIO；真机仍要求启用。
                Log.speech.warning("模拟器无法启用实时语音处理：\(error.localizedDescription)")
            }
            #else
            try inputNode.setVoiceProcessingEnabled(true)
            #endif

            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard VoiceRecorder.isRecordableInputFormat(inputFormat) else {
                throw RealtimeVoiceError.audioInputUnavailable
            }

            let runtime = RealtimeAudioInputRuntime { [weak self] level, timestamp in
                Task { @MainActor [weak self] in
                    self?.onLevel?(level, timestamp)
                }
            }
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: inputFormat
            ) { buffer, _ in
                runtime.receive(buffer)
            }

            self.recognizer = recognizer
            self.engine = engine
            self.runtime = runtime
            self.contextualStrings = Array(contextualStrings.prefix(100))
            self.prefersOnDeviceRecognition = true
            self.isRunning = true
            self.isMuted = false
            startRecognitionTask()
            engine.prepare()
            try engine.start()
        } catch let error as RealtimeVoiceError {
            await teardown()
            throw error
        } catch {
            Log.speech.error("实时语音输入启动失败：\(error.localizedDescription)")
            await teardown()
            throw RealtimeVoiceError.audioSessionFailed
        }
    }

    public func restartRecognition() {
        guard isRunning, !isMuted else { return }
        startRecognitionTask()
    }

    public func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        if muted {
            stopRecognitionTask()
            latestTranscript = ""
            onTranscript?("")
        } else if isRunning {
            startRecognitionTask()
        }
    }

    public func stop() async {
        await teardown()
    }

    private func startRecognitionTask() {
        stopRecognitionTask()
        guard let recognizer else { return }

        latestTranscript = ""
        onTranscript?("")
        recognitionGeneration = UUID()
        let generation = recognitionGeneration
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        activeRequestUsesOnDeviceRecognition = prefersOnDeviceRecognition
            && recognizer.supportsOnDeviceRecognition
        if activeRequestUsesOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        runtime?.replaceRequest(request)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleRecognitionCallback(
                    transcript: transcript,
                    isFinal: isFinal,
                    failure: failure,
                    generation: generation
                )
            }
        }
    }

    private func handleRecognitionCallback(
        transcript: String?,
        isFinal: Bool,
        failure: String?,
        generation: UUID
    ) {
        guard generation == recognitionGeneration, isRunning, !isMuted else { return }
        if let transcript {
            latestTranscript = transcript
            onTranscript?(transcript)
        }
        if let failure, !isFinal {
            if activeRequestUsesOnDeviceRecognition {
                // 某些真机虽然声明支持端上识别，但对应语言模型尚未下载；下一次恢复允许系统服务兜底。
                prefersOnDeviceRecognition = false
                Log.speech.info("端上语音识别不可用，下一次尝试切换系统识别服务")
            }
            Log.speech.warning("实时语音识别中断：\(failure)")
            onFailure?(failure)
        }
    }

    private func stopRecognitionTask() {
        runtime?.replaceRequest(nil)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        activeRequestUsesOnDeviceRecognition = false
        recognitionGeneration = UUID()
    }

    private func teardown() async {
        isRunning = false
        stopRecognitionTask()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        engine = nil
        runtime = nil
        recognizer = nil
        latestTranscript = ""
        onTranscript?("")
        await audioSession.deactivate()
    }

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
