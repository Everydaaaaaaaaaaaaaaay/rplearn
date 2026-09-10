@preconcurrency import CoreML
import CoreKit
import FluidAudio
import Foundation

enum Supertonic3SpeechEngineError: LocalizedError {
    case resourcesMissing
    case notReady

    var errorDescription: String? {
        switch self {
        case .resourcesMissing:
            "随包 Supertonic-3 模型缺失或损坏。"
        case .notReady:
            "Supertonic-3 尚未完成初始化。"
        }
    }
}

struct Supertonic3SynthesisBenchmarkResult: Sendable {
    let synthesisDuration: TimeInterval
    let audioDuration: TimeInterval
    let sampleCount: Int

    var realTimeFactor: Double {
        guard synthesisDuration > 0 else { return 0 }
        return audioDuration / synthesisDuration
    }
}

/// 固定为 ANE int4 三档模型。L128 覆盖单词与普通短句，较长句子可自动升到
/// L256/L512；因此同一套资源也能用于整句 NPC 台词的对比测试。
enum Supertonic3AssetSelection {
    static let maxSingleChunkCharacters = Supertonic3Constants.maxChunkLengthLatin
    static let repositoryFolder = Repo.supertonic3.folderName
    static let sampleRate = 44_100.0
    static let cachePipelineVersion = "supertonic-3-v1.7.3-ane-int4-44k1-steps8-cache-v2"

    static let requiredFileSizes: [String: Int64] = [
        "TextEncoder.mlmodelc/weights/weight.bin": 18_022_016,
        "DurationPredictor.mlmodelc/weights/weight.bin": 1_797_952,
        "Vocoder.mlmodelc/weights/weight.bin": 50_672_512,
        "VectorEstimatorVariants/VectorEstimator_L128_int4.mlmodelc/weights/weight.bin": 32_166_112,
        "VectorEstimatorVariants/VectorEstimator_L256_int4.mlmodelc/weights/weight.bin": 32_167_200,
        "VectorEstimatorVariants/VectorEstimator_L512_int4.mlmodelc/weights/weight.bin": 32_168_224,
        "tts.json": 8_253,
        "unicode_indexer.json": 277_676,
        "voice_styles/F1.json": 292_046,
        "voice_styles/F2.json": 292_423,
        "voice_styles/F3.json": 290_794,
        "voice_styles/F4.json": 291_808,
        "voice_styles/F5.json": 291_479,
        "voice_styles/M1.json": 291_748,
        "voice_styles/M2.json": 292_055,
        "voice_styles/M3.json": 290_198,
        "voice_styles/M4.json": 291_522,
        "voice_styles/M5.json": 291_469,
    ]
}

enum Supertonic3RuntimeAssetValidator {
    static func repositoryRoot(in modelsRoot: URL) -> URL {
        modelsRoot.appendingPathComponent(
            Supertonic3AssetSelection.repositoryFolder,
            isDirectory: true
        )
    }

    static func isRuntimeUsable(
        modelsRoot: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let repositoryRoot = repositoryRoot(in: modelsRoot)
        return Supertonic3AssetSelection.requiredFileSizes.allSatisfy {
            relativePath, expectedSize in
            guard let attributes = try? fileManager.attributesOfItem(
                atPath: repositoryRoot.appendingPathComponent(relativePath).path
            ), let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.int64Value == expectedSize
        }
    }
}

enum Supertonic3VoiceCatalog {
    static let allVoiceIDs: Set<String> = Set(
        (1...5).map { "F\($0)" } + (1...5).map { "M\($0)" }
    )

    struct Profile: Sendable, Equatable {
        let voiceID: String
        let speed: Float
        let silenceDuration: Float

        var cacheIdentity: String {
            "\(voiceID)-speed-\(String(format: "%.2f", speed))"
        }
    }

    static func profile(for request: SpeechRequest) -> Profile {
        // 词典发音固定使用同一音色，避免同一个单词因调用入口不同而换声。
        guard request.purpose != .pronunciation else {
            return Profile(voiceID: "F1", speed: 1.0, silenceDuration: 0.05)
        }
        if let voice = request.voiceHint?.supertonicVoice {
            return Profile(voiceID: voice.rawValue, speed: 1, silenceDuration: 0.05)
        }

        let candidates: [String]
        switch request.voiceHint?.gender?.lowercased() {
        case "female": candidates = (1...5).map { "F\($0)" }
        case "male": candidates = (1...5).map { "M\($0)" }
        default: candidates = ["F1", "M1", "F2", "M2", "F3", "M3", "F4", "M4", "F5", "M5"]
        }
        let key = request.voiceHint?.stableID ?? request.language
        let voiceID = candidates[stableIndex(key, upperBound: candidates.count)]

        // 同一基础音色再配合小幅语速差异，形成更多可辨识的角色表达档案。
        // 范围刻意保持克制，避免为了“不同”牺牲发音清晰度与自然度。
        let speeds: [Float] = [0.96, 1.00, 1.04, 1.08, 1.12]
        let speed = speeds[stableIndex("\(key)-delivery", upperBound: speeds.count)]
        return Profile(voiceID: voiceID, speed: speed, silenceDuration: 0.05)
    }

    static func stableIndex(_ value: String, upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        // FNV-1a，避免 Swift Hasher 的随机种子使 NPC 在不同启动间换声。
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(upperBound))
    }
}

/// Supertonic-3 的模型、音色、PCM 缓存与播放器边界。AdaptiveSpeechService
/// 只负责路由和跨引擎取消，不接触 Supertonic 的 Core ML 细节。
actor Supertonic3SpeechEngine {
    private let modelsRoot: URL
    private let audioSession: AudioSessionCoordinator
    private let apple: AppleTTSService
    private let audioCache: SpeechAudioCache

    private var manager: Supertonic3Manager?
    private var preparationTask: Task<Supertonic3Manager, Error>?
    private var warmupTask: Task<Void, Never>?
    private var didWarmUp = false
    private var voiceStyles: [String: Supertonic3VoiceStyle] = [:]
    private var player: SpeechPCMPlayer?
    private var playbackTask: Task<Void, Never>?

    init(
        modelsRoot: URL,
        audioCacheDirectory: URL,
        audioSession: AudioSessionCoordinator,
        apple: AppleTTSService
    ) {
        self.modelsRoot = modelsRoot
        self.audioSession = audioSession
        self.apple = apple
        self.audioCache = SpeechAudioCache(directory: audioCacheDirectory)
    }

    var resourcesAreComplete: Bool {
        Supertonic3RuntimeAssetValidator.isRuntimeUsable(
            modelsRoot: modelsRoot
        )
    }

    var isReady: Bool { manager != nil }

    func prepare() async throws {
        guard resourcesAreComplete else {
            throw Supertonic3SpeechEngineError.resourcesMissing
        }
        if manager == nil {
            let task: Task<Supertonic3Manager, Error>
            if let preparationTask {
                task = preparationTask
            } else {
                let modelsRoot = modelsRoot
                task = Task.detached(priority: .userInitiated) {
                    let manager = Supertonic3Manager(
                        directory: modelsRoot,
                        computeUnits: .cpuAndNeuralEngine,
                        vectorEstimator: .aneBucketed(.int4)
                    )
                    try await manager.initialize()
                    return manager
                }
                preparationTask = task
            }

            do {
                manager = try await task.value
                preparationTask = nil
            } catch {
                preparationTask = nil
                throw error
            }
        }
        await warmUpIfNeeded()
    }

    func speak(_ request: SpeechRequest, prepared: PreparedSpeech? = nil) async {
        await stopPlayback()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performPlayback(request, prepared: prepared)
        }
        playbackTask = task
    }

    func speakAndWait(_ request: SpeechRequest, prepared: PreparedSpeech? = nil) async {
        await speak(request, prepared: prepared)
        await waitUntilFinished()
    }

    func waitUntilFinished() async {
        if let playbackTask {
            await playbackTask.value
        }
    }

    func stopPlayback() async {
        let task = playbackTask
        playbackTask = nil
        task?.cancel()
        // A failed synthesis can be awaiting Apple playback inside this task.
        // Stop that fallback before joining it, otherwise a skipped story line
        // continues speaking and blocks the next request until its natural end.
        if task != nil { await apple.stopSpeaking() }
        if let player {
            await player.stop()
        }
        if let task { await task.value }
    }

    func cleanup() async {
        await stopPlayback()
        preparationTask?.cancel()
        preparationTask = nil
        warmupTask?.cancel()
        warmupTask = nil
        if let manager {
            await manager.cleanup()
        }
        manager = nil
        didWarmUp = false
        voiceStyles.removeAll()
    }

    /// Shared by playback and the opt-in local audition; no cache or player is
    /// involved, so audition results exercise the actual production renderer.
    func synthesizeSamples(_ request: SpeechRequest, totalSteps: Int = 8) async throws -> [Float] {
        try Task.checkCancellation()
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        try await prepare()
        guard let manager else { throw Supertonic3SpeechEngineError.notReady }
        try Task.checkCancellation()
        let profile = Supertonic3VoiceCatalog.profile(for: request)
        let style = try voiceStyle(profile.voiceID)
        let cue = request.narrativeDelivery
        let rate = Supertonic3AssetSelection.sampleRate
        var samples = [Float](repeating: 0, count: Int((cue?.leadingPause ?? 0) * rate))
        for segment in request.synthesisSegments {
            try Task.checkCancellation()
            let result = try await manager.synthesize(
                text: segment.text, language: "en", style: style,
                totalSteps: min(12, max(5, totalSteps)),
                speed: profile.speed * (cue?.speedMultiplier ?? 1),
                silenceDuration: profile.silenceDuration
            )
            try Task.checkCancellation()
            guard !result.samples.isEmpty else { throw Supertonic3SpeechEngineError.notReady }
            samples.append(contentsOf: result.samples)
            samples.append(contentsOf: repeatElement(0, count: Int(segment.silenceAfter * rate)))
        }
        samples.append(contentsOf: repeatElement(0, count: Int((cue?.trailingPause ?? 0) * rate)))
        return samples
    }

    /// 真机集成测试只测推理，不播放音频。
    func benchmarkSynthesis(_ request: SpeechRequest) async throws
        -> Supertonic3SynthesisBenchmarkResult {
        let startedAt = Date()
        let samples = try await synthesizeSamples(request)
        return Supertonic3SynthesisBenchmarkResult(
            synthesisDuration: Date().timeIntervalSince(startedAt),
            audioDuration: Double(samples.count) / Supertonic3AssetSelection.sampleRate,
            sampleCount: samples.count
        )
    }

    private func performPlayback(_ request: SpeechRequest, prepared: PreparedSpeech?) async {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var didBeginPlayback = false
        do {
            try await prepare()
            guard manager != nil else { throw Supertonic3SpeechEngineError.notReady }
            let profile = Supertonic3VoiceCatalog.profile(for: request)
            let cacheKey: SpeechAudioCacheKey? = SpeechAudioCachePolicy.shouldCache(
                text: trimmed,
                purpose: request.purpose
            ) ? SpeechAudioCacheKey(
                text: trimmed,
                language: request.language,
                voiceID: request.narrativeDelivery == nil ? profile.cacheIdentity
                    : profile.cacheIdentity + "-" + request.deliveryCacheIdentity,
                pipelineVersion: Supertonic3AssetSelection.cachePipelineVersion
            ) : nil

            let samples: [Float]
            if let prepared, prepared.request == request {
                samples = prepared.samples
            } else if let cacheKey, let cached = await audioCache.samples(for: cacheKey) {
                samples = cached
                Log.speech.notice("Supertonic-3 发音缓存命中，跳过模型推理")
            } else {
                let synthesisStartedAt = Date()
                samples = try await synthesizeSamples(request)
                try Task.checkCancellation()
                if let cacheKey, !samples.isEmpty {
                    await audioCache.insert(samples, for: cacheKey)
                }
                let elapsed = String(
                    format: "%.3f",
                    Date().timeIntervalSince(synthesisStartedAt)
                )
                let realTimeFactor = Date().timeIntervalSince(synthesisStartedAt) > 0
                    ? (Double(samples.count) / Supertonic3AssetSelection.sampleRate) / Date().timeIntervalSince(synthesisStartedAt)
                    : 0
                let speed = String(format: "%.2f", realTimeFactor)
                Log.speech.notice(
                    "Supertonic-3 合成耗时 \(elapsed, privacy: .public)s，速度 \(speed, privacy: .public)x"
                )
            }

            try Task.checkCancellation()
            let mode: AudioSessionCoordinator.Mode = request.purpose == .realtimeConversation
                ? .conversation
                : .playback
            try await audioSession.activate(mode)
            let player = try await playbackPlayer()
            try await player.prepare(playbackID: request.playbackID)
            if try await player.enqueue(samples) {
                didBeginPlayback = true
            }
            if await player.finishScheduling() {
                didBeginPlayback = true
            }
            await player.waitUntilFinished()
        } catch {
            if let player {
                await player.stop()
            }
            guard !Task.isCancelled else { return }
            Log.speech.error(
                "Supertonic-3 播放失败，回退系统语音：\(error.localizedDescription, privacy: .public)"
            )
            if !didBeginPlayback {
                await apple.speakAndWait(request)
            }
        }
    }

    private func warmUpIfNeeded() async {
        guard !didWarmUp, let manager else { return }
        if let warmupTask {
            await warmupTask.value
            return
        }

        let style: Supertonic3VoiceStyle
        do {
            style = try voiceStyle("F1")
        } catch {
            Log.speech.warning(
                "Supertonic-3 预热音色加载失败：\(error.localizedDescription, privacy: .public)"
            )
            return
        }

        let task = Task {
            let startedAt = Date()
            do {
                _ = try await manager.synthesize(
                    text: "Ready.",
                    language: "en",
                    style: style
                )
                let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
                Log.speech.notice(
                    "Supertonic-3 无声首轮推理完成，耗时 \(elapsed, privacy: .public)s"
                )
            } catch {
                guard !Task.isCancelled else { return }
                Log.speech.warning(
                    "Supertonic-3 首轮预热失败，将在首次播放时重试：\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        warmupTask = task
        await task.value
        warmupTask = nil
        didWarmUp = true
    }

    private func voiceStyle(_ voiceID: String) throws -> Supertonic3VoiceStyle {
        if let cached = voiceStyles[voiceID] { return cached }
        let url = Supertonic3RuntimeAssetValidator.repositoryRoot(in: modelsRoot)
            .appendingPathComponent("voice_styles", isDirectory: true)
            .appendingPathComponent("\(voiceID).json")
        let style = try Supertonic3VoiceStyle.load(from: url)
        voiceStyles[voiceID] = style
        return style
    }

    private func playbackPlayer() async throws -> SpeechPCMPlayer {
        if let player { return player }
        let newPlayer = try SpeechPCMPlayer(
            sampleRate: Supertonic3AssetSelection.sampleRate
        )
        player = newPlayer
        return newPlayer
    }
}
