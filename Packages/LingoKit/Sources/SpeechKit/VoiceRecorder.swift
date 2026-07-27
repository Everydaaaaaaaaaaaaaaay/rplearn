import AVFoundation
import CoreKit
import Foundation
import Observation
import Speech

private final class AudioBufferFileWriter: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var file: AVAudioFile?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: fileURL, settings: buffer.format.settings)
            }
            try file?.write(from: buffer)
        } catch {
            // Drop the audio file for this buffer; the speech recognition request still receives it.
        }
    }
}

/// 语音输入录制器：录制/转写状态机。
/// AVAudioEngine.inputNode tap 双路：① 写 .caf 供回放 ② feed SFSpeechRecognizer(en_US) 实时识别。
@MainActor
@Observable
public final class VoiceRecorder {
    public enum State: Equatable {
        case idle
        case denied
        case recording(inCancelZone: Bool)
        case transcribing
        case failed(String)
    }

    public struct Capture: Sendable, Equatable {
        public let fileName: String?
        public let duration: Double
        public let transcript: String

        public init(fileName: String?, duration: Double, transcript: String) {
            self.fileName = fileName
            self.duration = duration
            self.transcript = transcript
        }
    }

    public struct StartedCapture {
        let engine: AVAudioEngine?
        let audioFile: AVAudioFile?
        let recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
        let recognitionTask: SFSpeechRecognitionTask?
        let fileName: String?
        let hasInputTap: Bool

        public init(
            engine: AVAudioEngine?,
            audioFile: AVAudioFile?,
            recognitionRequest: SFSpeechAudioBufferRecognitionRequest?,
            recognitionTask: SFSpeechRecognitionTask?,
            fileName: String?,
            hasInputTap: Bool = false
        ) {
            self.engine = engine
            self.audioFile = audioFile
            self.recognitionRequest = recognitionRequest
            self.recognitionTask = recognitionTask
            self.fileName = fileName
            self.hasInputTap = hasInputTap
        }
    }

    public struct RuntimeCallbacks: Sendable {
        private let levelReporter: @Sendable (Double) -> Void
        private let recognitionReporter: @Sendable (String, Bool) -> Void
        private let recognitionFailureReporter: @Sendable () -> Void

        init(recorder: VoiceRecorder) {
            self.levelReporter = { [weak recorder] level in
                Task { @MainActor [weak recorder] in
                    recorder?.level = level
                }
            }
            self.recognitionReporter = { [weak recorder] transcript, isFinal in
                Task { @MainActor [weak recorder] in
                    guard let recorder else { return }
                    recorder.latestTranscript = transcript
                    if isFinal {
                        recorder.finalTranscriptContinuation?.resume(returning: transcript)
                        recorder.finalTranscriptContinuation = nil
                    }
                }
            }
            self.recognitionFailureReporter = { [weak recorder] in
                Task { @MainActor [weak recorder] in
                    guard let recorder else { return }
                    recorder.finalTranscriptContinuation?.resume(returning: recorder.latestTranscript)
                    recorder.finalTranscriptContinuation = nil
                }
            }
        }

        public func reportLevel(_ level: Double) {
            levelReporter(level)
        }

        public func reportRecognition(transcript: String, isFinal: Bool) {
            recognitionReporter(transcript, isFinal)
        }

        public func reportRecognitionFailure() {
            recognitionFailureReporter()
        }
    }

    public static let maxDuration: TimeInterval = 60

    public private(set) var state: State = .idle
    public private(set) var level: Double = 0
    public private(set) var elapsed: TimeInterval = 0
    /// 60s 自动截断的结果暂存：手势结束时优先取走。
    public private(set) var pendingAutoCapture: Capture?

    private let audioSession: AudioSessionCoordinator
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private var fileName: String?
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?
    private var latestTranscript = ""
    private var finalTranscriptContinuation: CheckedContinuation<String, Never>?
    private let permissionRequester: @MainActor (VoiceRecorder) async -> Bool
    private let captureStarter: @MainActor (VoiceRecorder) throws -> StartedCapture

    public init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
        self.permissionRequester = { recorder in
            await recorder.requestPermissions()
        }
        self.captureStarter = { recorder in
            try recorder.startSystemCapture()
        }
    }

    public init(
        audioSession: AudioSessionCoordinator,
        permissionRequester: @escaping @MainActor (VoiceRecorder) async -> Bool,
        captureStarter: @escaping @MainActor (VoiceRecorder) throws -> StartedCapture
    ) {
        self.audioSession = audioSession
        self.permissionRequester = permissionRequester
        self.captureStarter = captureStarter
    }

    // MARK: - 权限

    public func requestPermissions() async -> Bool {
        // 关键：系统回调在后台 TCC/XPC 队列触发。若续体闭包处于 @MainActor 隔离下（本类是
        // @MainActor），Swift 6 运行时会在错误执行器上断言崩溃（EXC_BREAKPOINT）。
        // 故把等待封装进 nonisolated 静态方法，闭包只 resume Sendable 续体，可安全跨线程。
        guard await Self.requestMicrophonePermission() else {
            state = .denied
            return false
        }
        guard await Self.requestSpeechAuthorization() else {
            state = .denied
            return false
        }
        return true
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

    // MARK: - 录制

    public func startRecording() async {
        guard state == .idle || state == .denied else { return }
        guard await permissionRequester(self) else { return }
        guard !Task.isCancelled else {
            state = .idle
            return
        }

        do {
            try await audioSession.activate(.record)
            guard !Task.isCancelled else {
                await audioSession.deactivate()
                state = .idle
                return
            }
            let capture = try captureStarter(self)

            self.engine = capture.engine
            self.audioFile = capture.audioFile
            self.recognitionRequest = capture.recognitionRequest
            self.recognitionTask = capture.recognitionTask
            self.fileName = capture.fileName
            self.hasInputTap = capture.hasInputTap
            self.startedAt = .now
            self.latestTranscript = ""
            self.pendingAutoCapture = nil
            self.elapsed = 0
            guard !Task.isCancelled else {
                await teardown(deleteFile: true)
                state = .idle
                return
            }
            state = .recording(inCancelZone: false)
            startTicker()
        } catch {
            Log.speech.error("录音启动失败：\(error)")
            state = .failed(error.localizedDescription)
            await teardown(deleteFile: true)
        }
    }

    public func setCancelZone(_ inZone: Bool) {
        guard case .recording = state else { return }
        state = .recording(inCancelZone: inZone)
    }

    /// 松手发送：停止录制，等待最终转写（3s 兜底）。
    public func finishRecording() async -> Capture? {
        if let pending = pendingAutoCapture {
            pendingAutoCapture = nil
            return pending
        }
        guard case .recording = state else { return nil }
        return await stopAndTranscribe()
    }

    /// 上滑取消：丢弃音频与转写。
    public func cancelRecording() async {
        pendingAutoCapture = nil
        guard case .recording = state else { return }
        await teardown(deleteFile: true)
        state = .idle
    }

    public func resetFailure() {
        if case .failed = state {
            state = .idle
        }
    }

    public func makeRuntimeCallbacks() -> RuntimeCallbacks {
        RuntimeCallbacks(recorder: self)
    }

    // MARK: - 私有

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                guard case .recording = self.state, let startedAt = self.startedAt else { return }
                self.elapsed = Date.now.timeIntervalSince(startedAt)
                if self.elapsed >= Self.maxDuration {
                    // 60s 自动截断：完成录制并暂存，待手势结束取走。
                    self.pendingAutoCapture = await self.stopAndTranscribe()
                    return
                }
            }
        }
    }

    private func stopAndTranscribe() async -> Capture? {
        let duration = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        let fileName = self.fileName
        state = .transcribing

        removeInputTapIfNeeded()
        engine?.stop()
        recognitionRequest?.endAudio()

        // 等待 isFinal（最多 3s），超时用最新部分结果兜底。
        let transcript = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            finalTranscriptContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                self.finalTranscriptContinuation?.resume(returning: self.latestTranscript)
                self.finalTranscriptContinuation = nil
            }
        }

        await teardown(deleteFile: false)

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, duration >= 0.5 else {
            if let fileName {
                VoiceMessageStorage.delete(fileName: fileName)
            }
            state = .failed("没有听清，请再试一次")
            return nil
        }
        state = .idle
        return Capture(fileName: fileName, duration: duration, transcript: trimmed)
    }

    private func teardown(deleteFile: Bool) async {
        ticker?.cancel()
        ticker = nil
        removeInputTapIfNeeded()
        engine?.stop()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        engine = nil
        audioFile = nil
        if deleteFile, let fileName {
            VoiceMessageStorage.delete(fileName: fileName)
        }
        fileName = nil
        startedAt = nil
        level = 0
        elapsed = 0
        await audioSession.deactivate()
    }

    public nonisolated static func isRecordableInputFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate.isFinite
            && format.sampleRate > 0
            && format.channelCount > 0
    }

    private func startSystemCapture() throws -> StartedCapture {
        try Self.startSystemCapture(callbacks: makeRuntimeCallbacks())
    }

    private nonisolated static func startSystemCapture(callbacks: RuntimeCallbacks) throws -> StartedCapture {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard Self.isRecordableInputFormat(format) else {
            throw RecorderError.unavailableInputFormat
        }

        let fileName = VoiceMessageStorage.newFileName()
        let fileURL = try VoiceMessageStorage.url(for: fileName)
        var installedTap = false

        do {
            let writer = AudioBufferFileWriter(fileURL: fileURL)

            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")),
                  recognizer.isAvailable else {
                throw NSError(domain: "VoiceRecorder", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "语音识别当前不可用",
                ])
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    callbacks.reportRecognition(
                        transcript: result.bestTranscription.formattedString,
                        isFinal: result.isFinal
                    )
                }
                if error != nil {
                    callbacks.reportRecognitionFailure()
                }
            }

            input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [callbacks, request, writer] buffer, _ in
                writer.write(buffer)
                request.append(buffer)
                if let channel = buffer.floatChannelData?[0] {
                    let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
                    let level = AudioLevelMeter.level(samples: samples)
                    callbacks.reportLevel(level)
                }
            }
            installedTap = true

            engine.prepare()
            try engine.start()

            return StartedCapture(
                engine: engine,
                audioFile: nil,
                recognitionRequest: request,
                recognitionTask: recognitionTask,
                fileName: fileName,
                hasInputTap: true
            )
        } catch {
            if installedTap {
                input.removeTap(onBus: 0)
            }
            VoiceMessageStorage.delete(fileName: fileName)
            throw error
        }
    }

    private func removeInputTapIfNeeded() {
        guard hasInputTap else { return }
        engine?.inputNode.removeTap(onBus: 0)
        hasInputTap = false
    }

    private enum RecorderError: LocalizedError {
        case unavailableInputFormat

        var errorDescription: String? {
            switch self {
            case .unavailableInputFormat:
                "当前麦克风输入不可用，请检查设备输入或使用模拟语音注入"
            }
        }
    }
}
