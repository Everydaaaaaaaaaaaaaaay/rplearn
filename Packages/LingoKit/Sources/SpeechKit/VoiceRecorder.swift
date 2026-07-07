import AVFoundation
import CoreKit
import Foundation
import Observation
import Speech

/// 语音输入录制器：录制/转写状态机（plan.md §3.2）。
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
    private var fileName: String?
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?
    private var latestTranscript = ""
    private var finalTranscriptContinuation: CheckedContinuation<String, Never>?

    public init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
    }

    // MARK: - 权限

    public func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            state = .denied
            return false
        }
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            state = .denied
            return false
        }
        return true
    }

    // MARK: - 录制

    public func startRecording() async {
        guard state == .idle || state == .denied else { return }
        guard await requestPermissions() else { return }

        do {
            try await audioSession.activate(.record)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)

            let fileName = VoiceMessageStorage.newFileName()
            let fileURL = try VoiceMessageStorage.url(for: fileName)
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)

            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")),
                  recognizer.isAvailable else {
                throw NSError(domain: "VoiceRecorder", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "语音识别当前不可用",
                ])
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.latestTranscript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.finalTranscriptContinuation?.resume(returning: self.latestTranscript)
                            self.finalTranscriptContinuation = nil
                        }
                    }
                    if error != nil {
                        self.finalTranscriptContinuation?.resume(returning: self.latestTranscript)
                        self.finalTranscriptContinuation = nil
                    }
                }
            }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, audioFile, request] buffer, _ in
                try? audioFile.write(from: buffer)
                request.append(buffer)
                if let channel = buffer.floatChannelData?[0] {
                    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                    let level = AudioLevelMeter.level(samples: samples)
                    Task { @MainActor [weak self] in
                        self?.level = level
                    }
                }
            }

            engine.prepare()
            try engine.start()

            self.engine = engine
            self.audioFile = audioFile
            self.recognitionRequest = request
            self.fileName = fileName
            self.startedAt = .now
            self.latestTranscript = ""
            self.pendingAutoCapture = nil
            self.elapsed = 0
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

        engine?.inputNode.removeTap(onBus: 0)
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
        engine?.inputNode.removeTap(onBus: 0)
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
}
