import CoreKit
import Foundation

public enum BundledSpeechModelPhase: Sendable, Equatable {
    case resourceMissing
    case available
    case loading
    case ready
    case failed
}

/// 设置页只依赖这个稳定状态，不接触 FluidAudio、Bundle 路径或具体模型文件。
public struct SpeechSynthesisEngineStatus: Sendable, Equatable {
    public let phase: BundledSpeechModelPhase
    public let bundledModelBytes: Int64
    public let selectedEngine: SpeechSynthesisEngine
    public let isBundledModelAvailable: Bool
    public let errorMessage: String?

    public init(
        phase: BundledSpeechModelPhase,
        bundledModelBytes: Int64 = 0,
        selectedEngine: SpeechSynthesisEngine,
        isBundledModelAvailable: Bool = false,
        errorMessage: String? = nil
    ) {
        self.phase = phase
        self.bundledModelBytes = bundledModelBytes
        self.selectedEngine = selectedEngine
        self.isBundledModelAvailable = isBundledModelAvailable
        self.errorMessage = errorMessage
    }

    public var isBusy: Bool { phase == .loading }

    public var isBundledEngineActive: Bool {
        phase == .ready && selectedEngine == .supertonic3
    }
}

/// 合成引擎选择与随包模型状态独立于日常播放协议，设置页不依赖具体推理实现。
public protocol SpeechSynthesisEngineManaging: Sendable {
    func synthesisEngineStatus() async -> SpeechSynthesisEngineStatus
    func synthesisEngineStatusUpdates() async -> AsyncStream<SpeechSynthesisEngineStatus>
    func selectSynthesisEngine(_ engine: SpeechSynthesisEngine) async
}

/// Supertonic-3 + Apple TTS 的可切换门面：
/// - 所有英语单词、NPC 台词和实时对话统一使用随包 Supertonic-3；
/// - 非英语、资源缺失或模型故障时立即使用 Apple；
/// - Bundle 路径、模型文件和 FluidAudio API 不泄漏到 Feature 层。
public actor AdaptiveSpeechService: SpeechService, SpeechSynthesisEngineManaging {
    private let apple: AppleTTSService
    private let supertonic: Supertonic3SpeechEngine
    private let supertonicModelDirectory: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager

    private var playbackRequestGate = SpeechPlaybackRequestGate()
    private var didInspectStorage = false
    private var status: SpeechSynthesisEngineStatus
    private var statusContinuations: [UUID: AsyncStream<SpeechSynthesisEngineStatus>.Continuation] = [:]

    public init(
        audioSession: AudioSessionCoordinator,
        supertonicModelDirectory: URL? = nil,
        supertonicAudioCacheDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        let apple = AppleTTSService(audioSession: audioSession)
        let modelsRoot = supertonicModelDirectory
            ?? Self.defaultSupertonicModelDirectory(fileManager: fileManager)
        self.apple = apple
        self.supertonicModelDirectory = modelsRoot
        self.defaults = defaults
        self.fileManager = fileManager
        self.supertonic = Supertonic3SpeechEngine(
            modelsRoot: modelsRoot,
            audioCacheDirectory: supertonicAudioCacheDirectory
                ?? Self.defaultSupertonicAudioCacheDirectory(fileManager: fileManager),
            audioSession: audioSession,
            apple: apple
        )
        self.status = SpeechSynthesisEngineStatus(
            phase: .resourceMissing,
            selectedEngine: VoiceEnginePreferences.synthesisEngine(defaults: defaults)
        )
    }

    /// App 启动后在后台加载模型并完成无声首轮推理，避免第一次点击承担冷启动成本。
    public func prepareForLaunch() async {
        await inspectStorageIfNeeded()
        guard status.isBundledModelAvailable, selectedEngine == .supertonic3 else { return }
        await prepareSupertonicIfNeeded(updateStatus: true)
    }

    public func speak(_ request: SpeechRequest) async {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let generation = playbackRequestGate.issue()
        await cancelCurrentPlayback()
        guard playbackRequestGate.accepts(generation) else { return }

        switch await resolvedEngine(for: request) {
        case .system:
            await apple.speak(request)
        case .supertonic3:
            await prepareSupertonicIfNeeded(updateStatus: selectedEngine == .supertonic3)
            guard playbackRequestGate.accepts(generation) else { return }
            guard await supertonic.isReady else {
                guard request.allowsSystemFallback else { return }
                await apple.speak(request)
                return
            }
            await supertonic.speak(request)
        }
    }

    public func prepareForPlayback(_ request: SpeechRequest) async -> PreparedSpeech? {
        guard !Task.isCancelled, request.purpose == .realtimeConversation,
              await resolvedEngine(for: request) == .supertonic3,
              !Task.isCancelled else { return nil }
        do {
            let samples = try await supertonic.synthesizeSamples(request)
            try Task.checkCancellation()
            return PreparedSpeech(request: request, samples: samples)
        } catch { return nil }
    }

    public func speakAndWait(_ request: SpeechRequest) async {
        await speakAndWait(request, prepared: nil)
    }

    public func speakAndWait(_ request: SpeechRequest, prepared: PreparedSpeech?) async {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let generation = playbackRequestGate.issue()
        await cancelCurrentPlayback()
        guard playbackRequestGate.accepts(generation), !Task.isCancelled else { return }
        let engine = await resolvedEngine(for: request)
        if engine == .supertonic3 {
            await prepareSupertonicIfNeeded(updateStatus: selectedEngine == .supertonic3)
        }
        guard playbackRequestGate.accepts(generation), !Task.isCancelled else { return }
        if engine == .supertonic3, await supertonic.isReady {
            await supertonic.speakAndWait(request, prepared: prepared)
        } else {
            guard request.allowsSystemFallback || request.engine != .supertonic3 else { return }
            // Await the actual fallback voice too; otherwise narrated pages advance
            // while Apple is still speaking when model preparation fails.
            await apple.speakAndWait(request)
        }
    }

    public func stopSpeaking() async {
        await invalidateCurrentPlayback()
    }

    public func refreshVoices() async {
        await apple.refreshVoices()
    }

    public func synthesisEngineStatus() async -> SpeechSynthesisEngineStatus {
        await inspectStorageIfNeeded()
        return status
    }

    public func synthesisEngineStatusUpdates() async -> AsyncStream<SpeechSynthesisEngineStatus> {
        await inspectStorageIfNeeded()
        let id = UUID()
        let pair = AsyncStream.makeStream(of: SpeechSynthesisEngineStatus.self)
        statusContinuations[id] = pair.continuation
        pair.continuation.yield(status)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusContinuation(id) }
        }
        return pair.stream
    }

    public func selectSynthesisEngine(_ engine: SpeechSynthesisEngine) async {
        await inspectStorageIfNeeded()
        guard engine == .system || status.isBundledModelAvailable else { return }
        VoiceEnginePreferences.setSynthesisEngine(engine, defaults: defaults)

        switch engine {
        case .supertonic3:
            await invalidateCurrentPlayback()
            await prepareSupertonicIfNeeded(updateStatus: true)
        case .system:
            await invalidateCurrentPlayback()
            await supertonic.cleanup()
            updateStatus(
                phase: status.isBundledModelAvailable ? .available : .resourceMissing,
                bundledModelBytes: bundledModelBytes,
                selectedEngine: .system,
                modelIsAvailable: status.isBundledModelAvailable
            )
        }
    }

    private func resolvedEngine(for request: SpeechRequest) async -> SpeechSynthesisEngine {
        guard request.language.lowercased().hasPrefix("en") else { return .system }
        return SpeechEngineRouter.resolve(
            request: request,
            selectedEngine: selectedEngine,
            supertonicIsAvailable: await supertonic.resourcesAreComplete
        )
    }

    private func cancelCurrentPlayback() async {
        await supertonic.stopPlayback()
        await apple.stopSpeaking()
    }

    private func invalidateCurrentPlayback() async {
        playbackRequestGate.invalidate()
        await cancelCurrentPlayback()
    }

    private func inspectStorageIfNeeded() async {
        guard !didInspectStorage else { return }
        didInspectStorage = true
        let resourcesAreComplete = await supertonic.resourcesAreComplete
        if resourcesAreComplete {
            updateStatus(
                phase: .available,
                bundledModelBytes: bundledModelBytes,
                selectedEngine: selectedEngine,
                modelIsAvailable: true
            )
        } else {
            VoiceEnginePreferences.setSynthesisEngine(.system, defaults: defaults)
            updateStatus(
                phase: .failed,
                bundledModelBytes: bundledModelBytes,
                selectedEngine: .system,
                modelIsAvailable: false,
                errorMessage: "随包 Supertonic-3 模型缺失或损坏。"
            )
        }
    }

    private var selectedEngine: SpeechSynthesisEngine {
        VoiceEnginePreferences.synthesisEngine(defaults: defaults)
    }

    private var bundledModelBytes: Int64 {
        directorySize(supertonicModelDirectory)
    }

    private func prepareSupertonicIfNeeded(updateStatus shouldUpdateStatus: Bool) async {
        if await supertonic.isReady {
            if shouldUpdateStatus {
                updateStatus(
                    phase: .ready,
                    bundledModelBytes: bundledModelBytes,
                    selectedEngine: .supertonic3,
                    modelIsAvailable: true
                )
            }
            return
        }

        if shouldUpdateStatus {
            updateStatus(
                phase: .loading,
                bundledModelBytes: bundledModelBytes,
                selectedEngine: .supertonic3,
                modelIsAvailable: true
            )
        }
        let startedAt = Date()
        do {
            try await supertonic.prepare()
            if shouldUpdateStatus {
                updateStatus(
                    phase: .ready,
                    bundledModelBytes: bundledModelBytes,
                    selectedEngine: .supertonic3,
                    modelIsAvailable: true
                )
            }
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
            Log.speech.notice(
                "Supertonic-3 初始化完成，总耗时 \(elapsed, privacy: .public)s"
            )
        } catch {
            if shouldUpdateStatus {
                updateStatus(
                    phase: .failed,
                    bundledModelBytes: bundledModelBytes,
                    selectedEngine: .supertonic3,
                    modelIsAvailable: true,
                    errorMessage: "Supertonic-3 加载失败，播放将继续使用系统语音。"
                )
            }
            Log.speech.error(
                "Supertonic-3 加载失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func updateStatus(
        phase: BundledSpeechModelPhase,
        bundledModelBytes: Int64,
        selectedEngine: SpeechSynthesisEngine,
        modelIsAvailable: Bool? = nil,
        errorMessage: String? = nil
    ) {
        status = SpeechSynthesisEngineStatus(
            phase: phase,
            bundledModelBytes: bundledModelBytes,
            selectedEngine: selectedEngine,
            isBundledModelAvailable: modelIsAvailable ?? status.isBundledModelAvailable,
            errorMessage: errorMessage
        )
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
    }

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations[id] = nil
    }

    private nonisolated static func defaultSupertonicModelDirectory(
        fileManager: FileManager
    ) -> URL {
        guard let directory = Bundle.module.url(
            forResource: "Supertonic3",
            withExtension: nil
        ) else {
            return fileManager.temporaryDirectory
                .appendingPathComponent("MissingSupertonic3Bundle", isDirectory: true)
        }
        return directory.appendingPathComponent("Models", isDirectory: true)
    }

    private nonisolated static func defaultSupertonicAudioCacheDirectory(
        fileManager: FileManager
    ) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("LingoTrip", isDirectory: true)
            .appendingPathComponent("Supertonic3Audio", isDirectory: true)
    }
}
