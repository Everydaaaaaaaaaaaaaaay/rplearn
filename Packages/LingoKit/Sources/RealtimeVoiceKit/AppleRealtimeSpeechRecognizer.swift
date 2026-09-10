@preconcurrency import AVFoundation
import CoreKit
import Foundation
import Speech
import SpeechKit

/// 音频 Tap 与 Speech request 由不同线程访问，用锁把非 Sendable 的 Apple 类型
/// 封装在模块内部，Feature 层只接触主线程回调。
private final class AppleSpeechInputRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let receiveLevel: @Sendable (Double) -> Void

    init(receiveLevel: @escaping @Sendable (Double) -> Void) {
        self.receiveLevel = receiveLevel
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

        guard let channel = buffer.floatChannelData?[0] else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        receiveLevel(AudioLevelMeter.level(samples: samples))
    }
}

/// AVAudioEngine 在实时音频队列调用 tap；从 MainActor 类型之外创建闭包，避免
/// Swift 6 把回调错误标记为主线程隔离并在首帧音频到达时触发运行时断言。
private func makeAppleSpeechAudioTap(
    runtime: AppleSpeechInputRuntime
) -> AVAudioNodeTapBlock {
    { buffer, _ in runtime.receive(buffer) }
}

/// Apple Speech 的实时输入实现。优先使用设备上的 Apple 识别模型；当前语言未安装
/// 端侧模型时允许 Apple 系统服务兜底。
@MainActor
public final class AppleRealtimeSpeechRecognizer: RealtimeSpeechInput {
    public var onLevel: (@MainActor @Sendable (Double) -> Void)?
    public var onSpeechStarted: (@MainActor @Sendable () -> Void)?
    public var onTranscription: (@MainActor @Sendable (RealtimeTranscription) -> Void)?
    public var onFailure: (@MainActor @Sendable (String) -> Void)?

    private let audioSession: AudioSessionCoordinator
    private let localeIdentifier: String
    private let contextualStrings: [String]

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var runtime: AppleSpeechInputRuntime?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionGeneration = UUID()
    private var restartTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var isRunning = false
    private var isMuted = false
    private var prefersOnDeviceRecognition = true
    private var activeRequestUsesOnDeviceRecognition = false
    private var speechGateOpen = false
    private var consecutiveVoiceChunks = 0
    private var latestTranscript = ""

    public init(
        audioSession: AudioSessionCoordinator,
        localeIdentifier: String = "en-US",
        contextualStrings: [String] = []
    ) {
        self.audioSession = audioSession
        self.localeIdentifier = localeIdentifier
        self.contextualStrings = Array(contextualStrings.prefix(100))
    }

    public func start() async throws {
        guard !isRunning else { return }
        guard await Self.requestMicrophonePermission() else {
            throw RealtimeVoiceError.microphonePermissionDenied
        }
        guard await Self.requestSpeechAuthorization() else {
            throw RealtimeVoiceError.speechRecognitionPermissionDenied
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable
        else { throw RealtimeVoiceError.speechRecognizerUnavailable }

        do {
            try await audioSession.activate(.conversation)
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode

            #if targetEnvironment(simulator)
            do {
                try inputNode.setVoiceProcessingEnabled(true)
            } catch {
                Log.speech.warning("模拟器无法启用实时语音处理：\(error.localizedDescription)")
            }
            #else
            try inputNode.setVoiceProcessingEnabled(true)
            #endif

            let format = inputNode.outputFormat(forBus: 0)
            guard VoiceRecorder.isRecordableInputFormat(format) else {
                throw RealtimeVoiceError.audioInputUnavailable
            }

            let runtime = AppleSpeechInputRuntime { [weak self] level in
                Task { @MainActor [weak self] in self?.receiveAudioLevel(level) }
            }
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: format,
                block: makeAppleSpeechAudioTap(runtime: runtime)
            )

            self.recognizer = recognizer
            self.audioEngine = engine
            self.runtime = runtime
            isRunning = true
            isMuted = false
            startRecognitionTask()
            engine.prepare()
            try engine.start()
        } catch let error as RealtimeVoiceError {
            await teardown()
            throw error
        } catch {
            Log.speech.error("Apple 实时语音输入启动失败：\(error.localizedDescription)")
            await teardown()
            throw RealtimeVoiceError.audioSessionFailed
        }
    }

    public func finishCurrentTurn() async {
        guard isRunning, !isMuted, let recognitionRequest else { return }
        runtime?.replaceRequest(nil)
        recognitionRequest.endAudio()
        let generation = recognitionGeneration
        finalizationTask?.cancel()
        finalizationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, self.recognitionGeneration == generation,
                  self.isRunning, !self.isMuted else { return }
            // endAudio is not guaranteed to produce a final callback. Commit the
            // latest measured transcript once and invalidate late callbacks.
            self.completeRecognitionTurn(self.latestTranscript)
        }
    }

    public func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        resetSpeechGate()
        if muted {
            stopRecognitionTask()
            onLevel?(0)
        } else if isRunning {
            startRecognitionTask()
        }
    }

    public func stop() async {
        await teardown()
    }

    private func startRecognitionTask() {
        stopRecognitionTask()
        guard isRunning, !isMuted, let recognizer else { return }

        recognitionGeneration = UUID()
        let generation = recognitionGeneration
        latestTranscript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        activeRequestUsesOnDeviceRecognition = prefersOnDeviceRecognition
            && recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = activeRequestUsesOnDeviceRecognition
        recognitionRequest = request
        runtime?.replaceRequest(request)

        recognitionTask = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeRecognitionHandler(owner: self, generation: generation)
        )
    }

    /// Speech framework 的 result handler 同样不承诺在主线程回调。先在非隔离
    /// 闭包中提取值，再显式切回 MainActor 更新会话状态。
    private nonisolated static func makeRecognitionHandler(
        owner: AppleRealtimeSpeechRecognizer,
        generation: UUID
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failure = error?.localizedDescription
            Task { @MainActor [weak owner] in
                owner?.handleRecognitionCallback(
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
        let normalized = transcript?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalized.isEmpty {
            latestTranscript = normalized
            if !isFinal { onTranscription?(.init(text: normalized, isFinal: false)) }
        }

        if isFinal {
            completeRecognitionTurn(latestTranscript)
            return
        }

        guard let failure else { return }
        if activeRequestUsesOnDeviceRecognition {
            // 有些设备声明支持端侧识别，但当前语言模型尚未安装。
            prefersOnDeviceRecognition = false
            Log.speech.info("Apple 端侧识别不可用，下一轮改用系统识别服务")
        }
        let recoveredTranscript = latestTranscript
        Log.speech.warning("Apple 实时语音识别中断并自动恢复：\(failure)")
        onFailure?(failure)
        completeRecognitionTurn(recoveredTranscript)
    }

    private func completeRecognitionTurn(_ text: String) {
        stopRecognitionTask()
        resetSpeechGate()
        if !text.isEmpty { onTranscription?(.init(text: text, isFinal: true)) }
        scheduleRecognitionRestart()
    }

    private func scheduleRecognitionRestart() {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.startRecognitionTask()
        }
    }

    private func stopRecognitionTask() {
        finalizationTask?.cancel()
        finalizationTask = nil
        restartTask?.cancel()
        restartTask = nil
        runtime?.replaceRequest(nil)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        activeRequestUsesOnDeviceRecognition = false
        recognitionGeneration = UUID()
        latestTranscript = ""
    }

    private func receiveAudioLevel(_ level: Double) {
        guard isRunning, !isMuted else { return }
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

    private func resetSpeechGate() {
        speechGateOpen = false
        consecutiveVoiceChunks = 0
    }

    private func teardown() async {
        isRunning = false
        stopRecognitionTask()
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            try? audioEngine.inputNode.setVoiceProcessingEnabled(false)
        }
        audioEngine = nil
        runtime = nil
        recognizer = nil
        resetSpeechGate()
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
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default:
            return false
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status != .notDetermined { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization {
                continuation.resume(returning: $0 == .authorized)
            }
        }
    }
}
