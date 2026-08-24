import CoreKit
import FluidAudio
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
        phase == .ready && selectedEngine == .pocketTTS
    }
}

/// 合成引擎选择与随包模型状态独立于日常播放协议，设置页不依赖具体推理实现。
public protocol SpeechSynthesisEngineManaging: Sendable {
    func synthesisEngineStatus() async -> SpeechSynthesisEngineStatus
    func synthesisEngineStatusUpdates() async -> AsyncStream<SpeechSynthesisEngineStatus>
    func selectSynthesisEngine(_ engine: SpeechSynthesisEngine) async
}

/// 随包固定模型版本只保留产品实际使用的 INT8 管线和 7 套音色。
enum PocketTTSAssetSelection {
    static let requiredFileSizes: [String: Int64] = [
        "cond_prefill.mlmodelc/weights/weight.bin": 133_237_248,
        "flow_decoder_fused.mlmodelc/weights/weight.bin": 19_012_608,
        "flowlm_stepv2.mlmodelc/weights/weight.bin": 76_809_280,
        "mimi_decoder.mlmodelc/weights/weight.bin": 41_768_256,
        "constants_bin/text_embed_table.bin": 16_388_096,
    ]
    static let voiceIDs: Set<String> = [
        "alba",
        "anna",
        "bill_boerst",
        "mary",
        "michael",
        "peter_yearsley",
        "stuart_bell",
    ]
}

enum PocketTTSRuntimeAssetValidator {
    /// 安装后的 App Bundle 可能被签名、瘦身或补充元数据，因此运行时不能再用
    /// “目录文件数/总字节必须完全相等”判定模型损坏。这里仅核对推理真正需要
    /// 的模型目录、常量、音色和大权重；发布前的精确哈希仍由构建脚本负责。
    static func isRuntimeUsable(
        at languageRoot: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let requiredModels = ModelNames.PocketTTS.requiredModels(
            precision: .int8,
            placement: .gpu
        )
        guard requiredModels.allSatisfy({
            fileManager.fileExists(atPath: languageRoot.appendingPathComponent($0).path)
        }) else { return false }

        let constants = languageRoot.appendingPathComponent("constants_bin", isDirectory: true)
        let requiredConstants = ["text_embed_table.bin", "tokenizer.model", "bos_emb.bin"]
        guard requiredConstants.allSatisfy({
            fileManager.fileExists(atPath: constants.appendingPathComponent($0).path)
        }) else { return false }

        guard PocketTTSAssetSelection.voiceIDs.allSatisfy({
            fileManager.fileExists(
                atPath: constants.appendingPathComponent("\($0).safetensors").path
            )
        }) else { return false }

        return PocketTTSAssetSelection.requiredFileSizes.allSatisfy {
            relativePath, expectedSize in
            guard let attributes = try? fileManager.attributesOfItem(
                atPath: languageRoot.appendingPathComponent(relativePath).path
            ), let size = attributes[.size] as? NSNumber
            else { return false }
            return size.int64Value == expectedSize
        }
    }
}

/// 角色 → Pocket 预设音色。口音先分英/美，再按角色稳定 ID 在同类音色中取值，
/// 同一角色跨启动保持一致；澳式暂选更接近的英式组，系统回退仍保留真正 en-AU。
enum PocketTTSVoiceCatalog {
    static func voiceID(language: String, hint: SpeechVoiceHint?) -> String {
        let gender = hint?.gender?.lowercased()
        let isBritishFamily = language.caseInsensitiveCompare("en-GB") == .orderedSame
            || language.caseInsensitiveCompare("en-AU") == .orderedSame

        let candidates: [String]
        switch (isBritishFamily, gender) {
        case (true, "male"):
            candidates = ["peter_yearsley", "stuart_bell"]
        case (true, "female"):
            candidates = ["alba", "anna"]
        case (false, "male"):
            candidates = ["michael", "bill_boerst"]
        case (false, "female"):
            candidates = ["mary"]
        case (true, _):
            candidates = ["alba", "peter_yearsley", "anna", "stuart_bell"]
        case (false, _):
            candidates = ["mary", "michael", "bill_boerst"]
        }

        guard candidates.count > 1 else { return candidates[0] }
        let key = hint?.stableID ?? language
        return candidates[stableIndex(key, upperBound: candidates.count)]
    }

    static func stableIndex(_ value: String, upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        // FNV-1a，避免 Swift Hasher 每次进程启动随机化导致角色换声。
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(upperBound))
    }
}

/// Pocket TTS + Apple TTS 的可切换门面：
/// - 模型随 App 安装，用户选择 Pocket 时后台预热；
/// - 非英语、未预热和故障均立即使用 Apple；
/// - Bundle 路径、模型文件和 FluidAudio API 不泄漏到 Feature 层。
public actor AdaptiveSpeechService: SpeechService, SpeechSynthesisEngineManaging {
    private let apple: AppleTTSService
    private let audioSession: AudioSessionCoordinator
    private var player: PocketTTSStreamingPlayer?
    private let modelDirectory: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager

    private var manager: PocketTtsManager?
    private var playbackTask: Task<Void, Never>?
    private var isManagingModel = false
    private var didInspectStorage = false
    private var status: SpeechSynthesisEngineStatus
    private var statusContinuations: [UUID: AsyncStream<SpeechSynthesisEngineStatus>.Continuation] = [:]

    public init(
        audioSession: AudioSessionCoordinator,
        modelDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.audioSession = audioSession
        self.apple = AppleTTSService(audioSession: audioSession)
        self.player = nil
        self.defaults = defaults
        self.fileManager = fileManager
        self.modelDirectory = modelDirectory ?? Self.defaultModelDirectory(fileManager: fileManager)
        self.status = SpeechSynthesisEngineStatus(
            phase: .resourceMissing,
            selectedEngine: VoiceEnginePreferences.synthesisEngine(defaults: defaults)
        )
    }

    /// App 启动后在后台调用。系统语音模式不加载 Pocket，减少启动内存占用。
    public func prepareForLaunch() async {
        await inspectStorageIfNeeded()
        guard status.isBundledModelAvailable,
              status.selectedEngine == .pocketTTS,
              manager == nil,
              !isManagingModel
        else { return }
        isManagingModel = true
        defer { isManagingModel = false }
        await loadBundledModel()
    }

    public func speak(_ request: SpeechRequest) async {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await cancelCurrentPlayback()
        await preparePocketIfNeeded(for: request)

        guard shouldUsePocket(for: request), let manager else {
            await apple.speak(request)
            return
        }

        let voiceID = PocketTTSVoiceCatalog.voiceID(
            language: request.language,
            hint: request.voiceHint
        )
        let player = await streamingPlayer()
        let oldTask = playbackTask
        let task = Task { [apple, audioSession, player] in
            if let oldTask { await oldTask.value }
            var didBeginPlayback = false
            var didReceiveFrame = false
            let synthesisStartedAt = Date()
            var firstFrameAt: Date?
            var previousFrameAt: Date?
            var firstFrameSampleCount = 0
            var generatedSampleCount = 0
            var slowFrameCount = 0
            var maximumFrameGap: TimeInterval = 0
            do {
                let stream = try await manager.synthesizeStreaming(
                    text: trimmed,
                    voice: voiceID,
                    temperature: 0.65
                )
                try Task.checkCancellation()
                let mode: AudioSessionCoordinator.Mode = request.purpose == .realtimeConversation
                    ? .conversation
                    : .playback
                try await audioSession.activate(mode)
                try await player.prepare()

                for try await frame in stream {
                    try Task.checkCancellation()
                    let frameArrivedAt = Date()
                    if !didReceiveFrame {
                        didReceiveFrame = true
                        firstFrameAt = frameArrivedAt
                        firstFrameSampleCount = frame.samples.count
                        let latency = String(
                            format: "%.3f",
                            frameArrivedAt.timeIntervalSince(synthesisStartedAt)
                        )
                        Log.speech.notice(
                            "Pocket TTS 首帧推理耗时 \(latency, privacy: .public)s"
                        )
                    }
                    if let previousFrameAt {
                        let gap = frameArrivedAt.timeIntervalSince(previousFrameAt)
                        maximumFrameGap = max(maximumFrameGap, gap)
                        if gap > 0.08 {
                            slowFrameCount += 1
                        }
                    }
                    previousFrameAt = frameArrivedAt
                    generatedSampleCount += frame.samples.count
                    if try await player.enqueue(frame.samples) {
                        didBeginPlayback = true
                    }
                }
                if await player.finishScheduling() {
                    didBeginPlayback = true
                }
                await player.waitUntilFinished()

                let finishedAt = Date()
                let steadyWallTime = firstFrameAt.map {
                    finishedAt.timeIntervalSince($0)
                } ?? 0
                let steadyAudioDuration = Double(
                    max(0, generatedSampleCount - firstFrameSampleCount)
                ) / Double(PocketTtsConstants.audioSampleRate)
                let steadySpeed = steadyWallTime > 0
                    ? steadyAudioDuration / steadyWallTime
                    : 0
                let speedText = String(format: "%.2f", steadySpeed)
                let gapText = String(format: "%.3f", maximumFrameGap)
                let underruns = await player.currentUnderrunCount()
                Log.speech.notice(
                    "Pocket TTS 持续速度 \(speedText, privacy: .public)x，最大帧间隔 \(gapText, privacy: .public)s，超 80ms 帧 \(slowFrameCount, privacy: .public)，播放欠载 \(underruns, privacy: .public) 次"
                )

                if !didBeginPlayback, !Task.isCancelled {
                    await apple.speakAndWait(request)
                }
            } catch {
                await player.stop()
                guard !Task.isCancelled else { return }
                Log.speech.error("Pocket TTS 播放失败，回退系统语音：\(error.localizedDescription, privacy: .public)")
                if !didBeginPlayback {
                    await apple.speakAndWait(request)
                }
            }
        }
        playbackTask = task
    }

    public func speakAndWait(_ request: SpeechRequest) async {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await preparePocketIfNeeded(for: request)
        guard shouldUsePocket(for: request) else {
            await cancelCurrentPlayback()
            await apple.speakAndWait(request)
            return
        }
        await speak(request)
        if let playbackTask {
            await playbackTask.value
        }
    }

    private func shouldUsePocket(for request: SpeechRequest) -> Bool {
        let selectedEngine = request.engine
            ?? VoiceEnginePreferences.synthesisEngine(defaults: defaults)
        return request.language.lowercased().hasPrefix("en")
            && selectedEngine == .pocketTTS
            && status.phase == .ready
            && manager != nil
    }

    private func preparePocketIfNeeded(for request: SpeechRequest) async {
        let selectedEngine = request.engine
            ?? VoiceEnginePreferences.synthesisEngine(defaults: defaults)
        guard selectedEngine == .pocketTTS,
              manager == nil,
              !isManagingModel,
              isModelComplete
        else { return }

        isManagingModel = true
        defer { isManagingModel = false }
        await loadBundledModel()
    }

    public func stopSpeaking() async {
        await cancelCurrentPlayback()
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

        if engine == .pocketTTS {
            if manager == nil, !isManagingModel {
                isManagingModel = true
                defer { isManagingModel = false }
                await loadBundledModel()
            } else {
                updateStatus(
                    phase: manager == nil ? .available : .ready,
                    bundledModelBytes: status.bundledModelBytes,
                    selectedEngine: .pocketTTS,
                    modelIsAvailable: true
                )
            }
        } else {
            await cancelCurrentPlayback()
            manager = nil
            let bundledModelIsAvailable = status.isBundledModelAvailable
            updateStatus(
                phase: bundledModelIsAvailable ? .available : .resourceMissing,
                bundledModelBytes: status.bundledModelBytes,
                selectedEngine: .system,
                modelIsAvailable: bundledModelIsAvailable
            )
        }
    }

    private func cancelCurrentPlayback() async {
        let task = playbackTask
        playbackTask = nil
        task?.cancel()
        if let player {
            await player.stop()
        }
        await apple.stopSpeaking()
        if let task { await task.value }
    }

    private func inspectStorageIfNeeded() async {
        guard !didInspectStorage else { return }
        didInspectStorage = true
        let bytes = directorySize(modelDirectory)
        if isModelComplete {
            updateStatus(
                phase: .available,
                bundledModelBytes: bytes,
                selectedEngine: selectedEngine,
                modelIsAvailable: true
            )
        } else {
            VoiceEnginePreferences.setSynthesisEngine(.system, defaults: defaults)
            updateStatus(
                phase: .failed,
                bundledModelBytes: bytes,
                selectedEngine: .system,
                modelIsAvailable: false,
                errorMessage: "随包 Pocket TTS 模型缺失或损坏。"
            )
        }
    }

    private func loadBundledModel() async {
        guard isModelComplete else {
            VoiceEnginePreferences.setSynthesisEngine(.system, defaults: defaults)
            updateStatus(
                phase: .failed,
                bundledModelBytes: directorySize(modelDirectory),
                selectedEngine: .system,
                modelIsAvailable: false,
                errorMessage: "随包 Pocket TTS 模型缺失或损坏。"
            )
            return
        }

        let bytes = directorySize(modelDirectory)
        updateStatus(
            phase: .loading,
            bundledModelBytes: bytes,
            selectedEngine: selectedEngine,
            modelIsAvailable: true
        )
        let loadStartedAt = Date()
        Log.speech.notice("Pocket TTS 开始加载 Core ML 模型")
        do {
            let newManager = PocketTtsManager(
                defaultVoice: "alba",
                language: .english,
                directory: modelDirectory,
                precision: .int8,
                placement: .gpu
            )
            try await newManager.initialize()
            await warmUpModel(newManager)
            manager = newManager
            updateStatus(
                phase: .ready,
                bundledModelBytes: bytes,
                selectedEngine: selectedEngine,
                modelIsAvailable: true
            )
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(loadStartedAt))
            Log.speech.notice(
                "Pocket TTS 初始化完成并可流式播放，总耗时 \(elapsed, privacy: .public)s"
            )
        } catch {
            manager = nil
            updateStatus(
                phase: .failed,
                bundledModelBytes: directorySize(modelDirectory),
                selectedEngine: selectedEngine,
                modelIsAvailable: true,
                errorMessage: "模型加载失败，播放将继续使用系统语音。"
            )
            Log.speech.error("Pocket TTS 加载失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Core ML 的首次 prediction 通常还有惰性编译/管线建立成本。模型加载后在
    /// 后台完整生成一个极短短句，同时把默认音色读入 FluidAudio 的缓存，避免
    /// 用户第一次点击时承担这两部分延迟。预热失败不影响模型进入 ready，真实
    /// 播放仍会沿用原有的 Apple TTS 回退路径。
    private func warmUpModel(_ manager: PocketTtsManager) async {
        #if targetEnvironment(simulator)
        return
        #else
        let startedAt = Date()
        do {
            let stream = try await manager.synthesizeStreaming(
                text: "Ready.",
                voice: "alba",
                temperature: 0.65
            )
            for try await _ in stream {
                try Task.checkCancellation()
            }
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
            Log.speech.notice(
                "Pocket TTS 无声首轮推理完成，耗时 \(elapsed, privacy: .public)s"
            )
        } catch {
            guard !Task.isCancelled else { return }
            Log.speech.warning(
                "Pocket TTS 首轮预热失败，将在首次播放时重试：\(error.localizedDescription, privacy: .public)"
            )
        }
        #endif
    }

    private func streamingPlayer() async -> PocketTTSStreamingPlayer {
        if let player { return player }
        let newPlayer = try! PocketTTSStreamingPlayer()
        player = newPlayer
        return newPlayer
    }

    private var languageRoot: URL {
        modelDirectory
            .appendingPathComponent(PocketTtsConstants.defaultModelsSubdirectory, isDirectory: true)
            .appendingPathComponent(Repo.pocketTts.folderName, isDirectory: true)
            .appendingPathComponent(PocketTtsLanguage.english.repoSubdirectory, isDirectory: true)
    }

    private var isModelComplete: Bool {
        PocketTTSRuntimeAssetValidator.isRuntimeUsable(
            at: languageRoot,
            fileManager: fileManager
        )
    }

    private var selectedEngine: SpeechSynthesisEngine {
        VoiceEnginePreferences.synthesisEngine(defaults: defaults)
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

    private nonisolated static func defaultModelDirectory(fileManager: FileManager) -> URL {
        guard let directory = Bundle.module.url(
            forResource: "PocketTTS",
            withExtension: nil
        ) else {
            // 状态检查会把缺失资源转成 failed；这里不把 Bundle 细节泄漏到调用方。
            return fileManager.temporaryDirectory
                .appendingPathComponent("MissingPocketTTSBundle", isDirectory: true)
        }
        return directory
    }
}
