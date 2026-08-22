import CoreKit
import FluidAudio
import Foundation

public enum OfflineSpeechModelPhase: Sendable, Equatable {
    case notInstalled
    case downloading
    case loading
    case installed
    case ready
    case failed
}

/// 设置页只依赖这个稳定状态，不接触 FluidAudio 或具体模型文件。
public struct OfflineSpeechModelStatus: Sendable, Equatable {
    public let phase: OfflineSpeechModelPhase
    public let progress: Double?
    public let installedBytes: Int64
    public let expectedDownloadBytes: Int64
    public let isEnabled: Bool
    public let isInstalled: Bool
    public let errorMessage: String?

    public init(
        phase: OfflineSpeechModelPhase,
        progress: Double? = nil,
        installedBytes: Int64 = 0,
        expectedDownloadBytes: Int64,
        isEnabled: Bool,
        isInstalled: Bool = false,
        errorMessage: String? = nil
    ) {
        self.phase = phase
        self.progress = progress
        self.installedBytes = installedBytes
        self.expectedDownloadBytes = expectedDownloadBytes
        self.isEnabled = isEnabled
        self.isInstalled = isInstalled
        self.errorMessage = errorMessage
    }

    public var isBusy: Bool {
        phase == .downloading || phase == .loading
    }

    public var isActive: Bool {
        phase == .ready && isEnabled
    }
}

/// 高品质离线模型的生命周期能力，与日常播放协议分离。
public protocol OfflineSpeechModelManaging: Sendable {
    func offlineModelStatus() async -> OfflineSpeechModelStatus
    func offlineModelStatusUpdates() async -> AsyncStream<OfflineSpeechModelStatus>
    func installOfflineModel() async
    func removeOfflineModel() async
    func setOfflineModelEnabled(_ enabled: Bool) async
}

private enum PocketTTSIntegrationError: LocalizedError {
    case insufficientStorage(available: Int64, required: Int64)
    case incompleteDownload

    var errorDescription: String? {
        switch self {
        case .insufficientStorage(let available, let required):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "可用空间不足。至少需要 \(formatter.string(fromByteCount: required))，当前约 \(formatter.string(fromByteCount: available))。"
        case .incompleteDownload:
            return "Pocket TTS 模型下载不完整，请检查网络后重试。"
        }
    }
}

/// 固定模型版本对应的资源选择策略。只保留产品实际使用的 INT8 管线和 7 套音色，
/// 避免 FluidAudio 默认英语仓库把未使用的 FP16/ANE 管线与全部音色一并下载。
enum PocketTTSAssetSelection {
    static let expectedDownloadBytes: Int64 = 332_000_000
    static let minimumFreeSpaceBytes: Int64 = 700_000_000
    static let voiceIDs: Set<String> = [
        "alba",
        "anna",
        "bill_boerst",
        "mary",
        "michael",
        "peter_yearsley",
        "stuart_bell",
    ]

    static func shouldSkip(remotePath path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        let name = components.last ?? path

        if name == ".DS_Store" || name == "verify.wav" {
            return true
        }
        if components.contains(where: { $0.hasSuffix(".mlpackage") }) {
            return true
        }
        if components.contains("constants") {
            return true
        }

        let excludedModelDirectories: Set<String> = [
            "flowlm_step.mlmodelc",        // FP16，已选用 INT8 flowlm_stepv2
            "flowlm_step_ane.mlmodelc",    // 额外的 FP16 ANE 变体
            "cond_prefill_ane.mlmodelc",   // 额外的 FP16 ANE 变体
            "pocket_state.mlmodelc",       // 尚未启用的实验性 MLState 管线
        ]
        if !excludedModelDirectories.isDisjoint(with: components) {
            return true
        }

        if name.hasSuffix(".safetensors") {
            let voiceID = String(name.dropLast(".safetensors".count))
            return !voiceIDs.contains(voiceID)
        }
        return false
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

/// Pocket TTS + Apple TTS 的自适应门面：
/// - 角色台词优先使用已预热的 Pocket 流式模型；
/// - 单词/发音练习、非英语、未安装、未预热和故障均立即使用 Apple；
/// - 下载、模型文件和 FluidAudio API 不泄漏到 Feature 层。
public actor AdaptiveSpeechService: SpeechService, OfflineSpeechModelManaging {
    public static let enabledPreferenceKey = "lingotrip.pocketTTS.enabled"

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
    private var status: OfflineSpeechModelStatus
    private var statusContinuations: [UUID: AsyncStream<OfflineSpeechModelStatus>.Continuation] = [:]

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
        self.status = OfflineSpeechModelStatus(
            phase: .notInstalled,
            expectedDownloadBytes: PocketTTSAssetSelection.expectedDownloadBytes,
            isEnabled: defaults.bool(forKey: Self.enabledPreferenceKey)
        )
    }

    /// App 启动后在后台调用。加载未完成时播放绝不等待，仍会直接走 Apple。
    public func prepareForLaunch() async {
        await inspectStorageIfNeeded()
        guard status.isInstalled, status.isEnabled, manager == nil, !isManagingModel else { return }
        isManagingModel = true
        defer { isManagingModel = false }
        await loadInstalledModel()
    }

    public func speak(_ request: SpeechRequest) async {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await cancelCurrentPlayback()

        guard request.purpose != .pronunciation,
              request.language.lowercased().hasPrefix("en"),
              status.isEnabled,
              status.phase == .ready,
              let manager
        else {
            await apple.speak(request)
            // 模型已经落盘但尚未预热时，后台补做初始化；本次点击不等待。
            if status.isEnabled,
               status.phase == .installed,
               manager == nil,
               !isManagingModel {
                Task { [weak self] in await self?.prepareForLaunch() }
            }
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
                try await audioSession.activate(.playback)
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
                    await apple.speak(request)
                }
            } catch {
                await player.stop()
                guard !Task.isCancelled else { return }
                Log.speech.error("Pocket TTS 播放失败，回退系统语音：\(error.localizedDescription, privacy: .public)")
                if !didBeginPlayback {
                    await apple.speak(request)
                }
            }
        }
        playbackTask = task
    }

    public func stopSpeaking() async {
        await cancelCurrentPlayback()
    }

    public func refreshVoices() async {
        await apple.refreshVoices()
    }

    public func offlineModelStatus() async -> OfflineSpeechModelStatus {
        await inspectStorageIfNeeded()
        return status
    }

    public func offlineModelStatusUpdates() async -> AsyncStream<OfflineSpeechModelStatus> {
        await inspectStorageIfNeeded()
        let id = UUID()
        let pair = AsyncStream.makeStream(of: OfflineSpeechModelStatus.self)
        statusContinuations[id] = pair.continuation
        pair.continuation.yield(status)
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusContinuation(id) }
        }
        return pair.stream
    }

    public func installOfflineModel() async {
        guard !isManagingModel else { return }
        isManagingModel = true
        defer { isManagingModel = false }

        await cancelCurrentPlayback()
        let currentBytes = directorySize(modelDirectory)
        updateStatus(
            phase: .downloading,
            progress: 0,
            installedBytes: currentBytes,
            isEnabled: status.isEnabled,
            errorMessage: nil
        )

        do {
            try ensureEnoughFreeSpace()
            try prepareModelDirectory()
            let repoDirectory = modelDirectory
                .appendingPathComponent(PocketTtsConstants.defaultModelsSubdirectory, isDirectory: true)
                .appendingPathComponent(Repo.pocketTts.folderName, isDirectory: true)
            try fileManager.createDirectory(at: repoDirectory, withIntermediateDirectories: true)

            try await ModelHub.download(
                .pocketTts,
                subdirectory: PocketTtsLanguage.english.repoSubdirectory,
                to: repoDirectory,
                progressHandler: { [weak self] progress in
                    Task { await self?.reportDownloadProgress(progress.fractionCompleted) }
                },
                shouldSkip: PocketTTSAssetSelection.shouldSkip(remotePath:)
            )

            guard isModelComplete else {
                throw PocketTTSIntegrationError.incompleteDownload
            }
            defaults.set(true, forKey: Self.enabledPreferenceKey)
            try excludeModelDirectoryFromBackup()
            await loadInstalledModel()
        } catch {
            manager = nil
            let bytes = directorySize(modelDirectory)
            updateStatus(
                phase: .failed,
                installedBytes: bytes,
                isEnabled: defaults.bool(forKey: Self.enabledPreferenceKey),
                modelIsInstalled: isModelComplete,
                errorMessage: userFacingMessage(for: error)
            )
            Log.speech.error("Pocket TTS 安装失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    public func removeOfflineModel() async {
        guard !isManagingModel else { return }
        isManagingModel = true
        defer { isManagingModel = false }

        await cancelCurrentPlayback()
        manager = nil
        do {
            if fileManager.fileExists(atPath: modelDirectory.path) {
                try fileManager.removeItem(at: modelDirectory)
            }
            defaults.set(false, forKey: Self.enabledPreferenceKey)
            didInspectStorage = true
            updateStatus(
                phase: .notInstalled,
                installedBytes: 0,
                isEnabled: false,
                modelIsInstalled: false
            )
        } catch {
            updateStatus(
                phase: .failed,
                installedBytes: directorySize(modelDirectory),
                isEnabled: false,
                modelIsInstalled: isModelComplete,
                errorMessage: "删除模型失败，请稍后重试。"
            )
            Log.speech.error("Pocket TTS 删除失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    public func setOfflineModelEnabled(_ enabled: Bool) async {
        await inspectStorageIfNeeded()
        guard status.isInstalled else { return }
        defaults.set(enabled, forKey: Self.enabledPreferenceKey)

        if enabled {
            if manager == nil, !isManagingModel {
                isManagingModel = true
                defer { isManagingModel = false }
                await loadInstalledModel()
            } else {
                updateStatus(
                    phase: manager == nil ? .installed : .ready,
                    installedBytes: status.installedBytes,
                    isEnabled: true
                )
            }
        } else {
            await cancelCurrentPlayback()
            manager = nil
            updateStatus(
                phase: .installed,
                installedBytes: directorySize(modelDirectory),
                isEnabled: false,
                modelIsInstalled: true
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
                phase: .installed,
                installedBytes: bytes,
                isEnabled: defaults.bool(forKey: Self.enabledPreferenceKey),
                modelIsInstalled: true
            )
        } else {
            updateStatus(
                phase: .notInstalled,
                installedBytes: bytes,
                isEnabled: false,
                modelIsInstalled: false
            )
        }
    }

    private func loadInstalledModel() async {
        guard isModelComplete else {
            updateStatus(
                phase: .notInstalled,
                installedBytes: directorySize(modelDirectory),
                isEnabled: false,
                modelIsInstalled: false
            )
            return
        }

        let bytes = directorySize(modelDirectory)
        updateStatus(
            phase: .loading,
            installedBytes: bytes,
            isEnabled: defaults.bool(forKey: Self.enabledPreferenceKey),
            modelIsInstalled: true
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
                progress: 1,
                installedBytes: bytes,
                isEnabled: defaults.bool(forKey: Self.enabledPreferenceKey),
                modelIsInstalled: true
            )
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(loadStartedAt))
            Log.speech.notice(
                "Pocket TTS 初始化完成并可流式播放，总耗时 \(elapsed, privacy: .public)s"
            )
        } catch {
            manager = nil
            updateStatus(
                phase: .failed,
                installedBytes: directorySize(modelDirectory),
                isEnabled: defaults.bool(forKey: Self.enabledPreferenceKey),
                modelIsInstalled: true,
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

    private func reportDownloadProgress(_ progress: Double) {
        guard status.phase == .downloading else { return }
        updateStatus(
            phase: .downloading,
            progress: min(max(progress, 0), 1),
            installedBytes: status.installedBytes,
            isEnabled: status.isEnabled
        )
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

        return PocketTTSAssetSelection.voiceIDs.allSatisfy {
            fileManager.fileExists(
                atPath: constants.appendingPathComponent("\($0).safetensors").path
            )
        }
    }

    private func ensureEnoughFreeSpace() throws {
        let probe = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? modelDirectory.deletingLastPathComponent()
        let values = try probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        let existing = directorySize(modelDirectory)
        let additionallyRequired = max(0, PocketTTSAssetSelection.minimumFreeSpaceBytes - existing)
        guard available >= additionallyRequired else {
            throw PocketTTSIntegrationError.insufficientStorage(
                available: available,
                required: additionallyRequired
            )
        }
    }

    private func prepareModelDirectory() throws {
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try excludeModelDirectoryFromBackup()
    }

    private func excludeModelDirectoryFromBackup() throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = modelDirectory
        try directory.setResourceValues(values)
    }

    private func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            total += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localized = error as? PocketTTSIntegrationError {
            return localized.localizedDescription
        }
        if error is CancellationError {
            return "模型下载已取消，可稍后继续。"
        }
        return "模型下载失败，请检查网络和可用空间后重试。"
    }

    private func updateStatus(
        phase: OfflineSpeechModelPhase,
        progress: Double? = nil,
        installedBytes: Int64,
        isEnabled: Bool,
        modelIsInstalled: Bool? = nil,
        errorMessage: String? = nil
    ) {
        status = OfflineSpeechModelStatus(
            phase: phase,
            progress: progress,
            installedBytes: installedBytes,
            expectedDownloadBytes: PocketTTSAssetSelection.expectedDownloadBytes,
            isEnabled: isEnabled,
            isInstalled: modelIsInstalled ?? status.isInstalled,
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
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("LingoTrip", isDirectory: true)
            .appendingPathComponent("Speech", isDirectory: true)
            .appendingPathComponent("PocketTTS", isDirectory: true)
    }
}
