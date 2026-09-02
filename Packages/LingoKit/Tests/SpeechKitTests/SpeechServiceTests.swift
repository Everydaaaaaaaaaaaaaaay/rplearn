import AVFoundation
import CoreKit
import Foundation
import Testing
@testable import SpeechKit

@Suite("AppleTTS 语音选择")
struct SpeechServiceTests {
    typealias Candidate = (language: String, qualityRank: Int, name: String)

    @Test("高速播放请求只允许最后一次继续")
    func rapidRequestsKeepLatest() {
        var gate = SpeechPlaybackRequestGate()
        let first = gate.issue()
        let second = gate.issue()

        #expect(!gate.accepts(first))
        #expect(gate.accepts(second))

        gate.invalidate()
        #expect(!gate.accepts(second))
    }

    @Test("没有英语语音时返回 nil")
    func noEnglishVoices() {
        let candidates: [Candidate] = [("zh-CN", 3, "Tingting"), ("fr-FR", 2, "Amelie")]
        #expect(AppleTTSService.rankBestIndex(candidates: candidates, target: "en-US") == nil)
    }

    @Test("全是标准音时保留目标口音")
    func allStandardPrefersAccent() {
        let candidates: [Candidate] = [("en-US", 1, "Fred"), ("en-GB", 1, "Daniel")]
        // 都不自然：口音匹配优先，选 en-US（下标 0），即使 en-GB 是优先命名。
        #expect(AppleTTSService.rankBestIndex(candidates: candidates, target: "en-US") == 0)
    }

    @Test("目标口音已有增强音则口音自然两全")
    func sameAccentEnhancedWins() {
        let candidates: [Candidate] = [("en-US", 1, "Fred"), ("en-US", 2, "Ava")]
        #expect(AppleTTSService.rankBestIndex(candidates: candidates, target: "en-US") == 1)
    }

    @Test("目标口音仅标准音、他口音有高级音时自然度优先跨口音")
    func naturalCrossesAccentWhenTargetIsRobotic() {
        let candidates: [Candidate] = [("en-US", 1, "Fred"), ("en-GB", 3, "Serena")]
        // en-US 只有机械音，en-GB 是高级音 → 宁可换口音也用自然音。
        #expect(AppleTTSService.rankBestIndex(candidates: candidates, target: "en-US") == 1)
    }

    @Test("目标口音已自然时不因他口音更高质量而换口音")
    func keepsAccentWhenAlreadyNatural() {
        let candidates: [Candidate] = [("en-US", 2, "Ava"), ("en-GB", 3, "Serena")]
        // en-US 已是增强音 → 保留美音，不追 en-GB 的高级音。
        #expect(AppleTTSService.rankBestIndex(candidates: candidates, target: "en-US") == 0)
    }

    @Test("同口音同质量时优先命名者胜出")
    func preferredNameBreaksTie() {
        let candidates: [Candidate] = [("en-US", 2, "Nicky"), ("en-US", 2, "Ava")]
        #expect(AppleTTSService.rankBestIndex(candidates: candidates, target: "en-US") == 1)
    }

    @Test("质量档映射与自然度判定")
    func qualityMapping() {
        #expect(VoiceReport.Quality(quality: .premium) == .premium)
        #expect(VoiceReport.Quality(quality: .enhanced) == .enhanced)
        #expect(VoiceReport.Quality(quality: .default) == .standard)
        #expect(VoiceReport.Quality.premium.isNatural)
        #expect(VoiceReport.Quality.enhanced.isNatural)
        #expect(!VoiceReport.Quality.standard.isNatural)
        #expect(!VoiceReport.Quality.unavailable.isNatural)
        #expect(VoiceReport.Quality.premium > .enhanced)
        #expect(VoiceReport.Quality.standard > .unavailable)
    }

    @Test("Supertonic 音色与语速按角色稳定选择并尊重性别")
    func supertonicVoiceProfileSelection() {
        let male = SpeechVoiceHint(
            stableID: "oliver",
            gender: "male",
            nationality: "British"
        )
        let female = SpeechVoiceHint(
            stableID: "casey",
            gender: "female",
            nationality: "American"
        )

        let maleRequest = SpeechRequest(
            text: "Hello",
            purpose: .characterDialogue,
            voiceHint: male
        )
        let first = Supertonic3VoiceCatalog.profile(for: maleRequest)
        let second = Supertonic3VoiceCatalog.profile(for: maleRequest)
        #expect(first == second)
        #expect(first.voiceID.hasPrefix("M"))
        #expect((0.96...1.12).contains(first.speed))

        let femaleProfile = Supertonic3VoiceCatalog.profile(
            for: SpeechRequest(
                text: "Hello",
                purpose: .characterDialogue,
                voiceHint: female
            )
        )
        #expect(femaleProfile.voiceID.hasPrefix("F"))

        let pronunciation = Supertonic3VoiceCatalog.profile(
            for: SpeechRequest(text: "extraordinary", purpose: .pronunciation)
        )
        #expect(pronunciation.voiceID == "F1")
        #expect(pronunciation.speed == 1.0)
    }

    @Test("TTS 引擎默认值、持久化和旧设置迁移保持稳定")
    func voiceEnginePreferences() {
        let suiteName = "SpeechServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(VoiceEnginePreferences.synthesisEngine(defaults: defaults) == .supertonic3)

        VoiceEnginePreferences.setSynthesisEngine(.system, defaults: defaults)
        #expect(VoiceEnginePreferences.synthesisEngine(defaults: defaults) == .system)

        VoiceEnginePreferences.setSynthesisEngine(.supertonic3, defaults: defaults)
        #expect(VoiceEnginePreferences.synthesisEngine(defaults: defaults) == .supertonic3)

        defaults.set("pocketTTS", forKey: VoiceEnginePreferences.synthesisEngineKey)
        #expect(VoiceEnginePreferences.synthesisEngine(defaults: defaults) == .supertonic3)

        defaults.removeObject(forKey: VoiceEnginePreferences.synthesisEngineKey)
        defaults.set(true, forKey: "lingotrip.pocketTTS.enabled")
        #expect(VoiceEnginePreferences.synthesisEngine(defaults: defaults) == .supertonic3)
    }

    @Test("试听请求可以临时覆盖全局 TTS 引擎")
    func speechRequestEngineOverride() {
        let request = SpeechRequest(text: "Hello", engine: .system)
        #expect(request.engine == .system)
    }

    @Test("所有英语用途统一路由到 Supertonic")
    func allEnglishPurposesUseSupertonic() {
        let requests = [
            SpeechRequest(text: "Hello", purpose: .general),
            SpeechRequest(text: "Welcome aboard.", purpose: .characterDialogue),
            SpeechRequest(text: "extraordinary", purpose: .pronunciation),
            SpeechRequest(text: "How are you?", purpose: .realtimeConversation),
        ]

        for request in requests {
            #expect(
                SpeechEngineRouter.resolve(
                    request: request,
                    selectedEngine: .supertonic3,
                    supertonicIsAvailable: true
                ) == .supertonic3
            )
        }
    }

    @Test("系统总开关、请求级覆盖和资源回退保持明确")
    func explicitSpeechRoutingAndFallback() {
        let pronunciation = SpeechRequest(text: "hello", purpose: .pronunciation)
        let explicitSupertonic = SpeechRequest(
            text: "hello",
            purpose: .pronunciation,
            engine: .supertonic3
        )

        #expect(
            SpeechEngineRouter.resolve(
                request: pronunciation,
                selectedEngine: .system,
                supertonicIsAvailable: true
            ) == .system
        )
        #expect(
            SpeechEngineRouter.resolve(
                request: explicitSupertonic,
                selectedEngine: .system,
                supertonicIsAvailable: true
            ) == .supertonic3
        )
        #expect(
            SpeechEngineRouter.resolve(
                request: explicitSupertonic,
                selectedEngine: .system,
                supertonicIsAvailable: false
            ) == .system
        )
    }

    @Test("安装资源包含 Supertonic-3 ANE int4 三档关键权重和音色")
    func bundledSupertonicModelsAreComplete() {
        let modelsRoot = Bundle.main.bundleURL
            .appendingPathComponent("LingoKit_SpeechKit.bundle", isDirectory: true)
            .appendingPathComponent("Supertonic3/Models", isDirectory: true)
        #expect(Supertonic3RuntimeAssetValidator.isRuntimeUsable(modelsRoot: modelsRoot))

        let repositoryRoot = Supertonic3RuntimeAssetValidator.repositoryRoot(in: modelsRoot)
        for voiceID in Supertonic3VoiceCatalog.allVoiceIDs {
            #expect(
                FileManager.default.fileExists(
                    atPath: repositoryRoot
                        .appendingPathComponent("voice_styles/\(voiceID).json")
                        .path
                )
            )
        }
    }

    @Test("Supertonic-3 在真机完成单词和整句推理")
    func supertonicDeviceSynthesisBenchmark() async throws {
        #if targetEnvironment(simulator)
        return
        #else
        let modelsRoot = Bundle.main.bundleURL
            .appendingPathComponent("LingoKit_SpeechKit.bundle", isDirectory: true)
            .appendingPathComponent("Supertonic3/Models", isDirectory: true)
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("SupertonicDeviceBenchmark-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cache) }
        let audioSession = AudioSessionCoordinator()
        let engine = Supertonic3SpeechEngine(
            modelsRoot: modelsRoot,
            audioCacheDirectory: cache,
            audioSession: audioSession,
            apple: AppleTTSService(audioSession: audioSession)
        )

        let initializationStartedAt = Date()
        try await engine.prepare()
        let initializationDuration = Date().timeIntervalSince(initializationStartedAt)
        let word = try await engine.benchmarkSynthesis(
            SpeechRequest(text: "extraordinary", purpose: .pronunciation)
        )
        let sentence = try await engine.benchmarkSynthesis(
            SpeechRequest(
                text: "Hey! It's lovely to meet you. Fancy exploring the city together?",
                purpose: .characterDialogue,
                voiceHint: SpeechVoiceHint(stableID: "benchmark", gender: "female")
            )
        )

        print(
            String(
                format: "SUPERTONIC_BENCHMARK init=%.3fs word=%.3fs/%.2fx sentence=%.3fs/%.2fx",
                initializationDuration,
                word.synthesisDuration,
                word.realTimeFactor,
                sentence.synthesisDuration,
                sentence.realTimeFactor
            )
        )
        #expect(word.sampleCount > 0)
        #expect(sentence.sampleCount > word.sampleCount)
        #expect(word.synthesisDuration < 2.0)
        #expect(sentence.synthesisDuration < 3.0)
        #endif
    }

    @Test("运行时模型校验允许安装器加入非关键文件")
    func runtimeModelValidationAllowsInstallerMetadata() throws {
        let fileManager = FileManager.default
        let modelsRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SupertonicValidation-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: modelsRoot) }
        let root = Supertonic3RuntimeAssetValidator.repositoryRoot(in: modelsRoot)

        for (relativePath, byteCount) in Supertonic3AssetSelection.requiredFileSizes {
            let url = root.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            #expect(fileManager.createFile(atPath: url.path, contents: Data()))
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(byteCount))
            try handle.close()
        }

        let installerMetadata = root.appendingPathComponent("installer-metadata.plist")
        #expect(fileManager.createFile(atPath: installerMetadata.path, contents: Data([0])))
        #expect(Supertonic3RuntimeAssetValidator.isRuntimeUsable(modelsRoot: modelsRoot))
    }

    @Test("PCM 播放器只等待短缓冲并在收尾时立即开播")
    func pcmPlaybackBufferPolicy() {
        let sampleRate = 100.0

        #expect(
            !SpeechPCMPlaybackBufferPolicy.shouldStart(
                bufferedSampleCount: 23,
                sampleRate: sampleRate,
                producerDidFinish: false
            )
        )
        #expect(
            SpeechPCMPlaybackBufferPolicy.shouldStart(
                bufferedSampleCount: 24,
                sampleRate: sampleRate,
                producerDidFinish: false
            )
        )
        #expect(
            SpeechPCMPlaybackBufferPolicy.shouldStart(
                bufferedSampleCount: 1,
                sampleRate: sampleRate,
                producerDidFinish: true
            )
        )
    }

    @Test("Supertonic 单词发音缓存跨实例复用 PCM")
    func supertonicPronunciationCachePersists() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechAudioCache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = SpeechAudioCacheKey(
            text: "hello",
            language: "en-US",
            voiceID: "F1-speed-1.00",
            pipelineVersion: Supertonic3AssetSelection.cachePipelineVersion
        )
        let expected: [Float] = [0, 0.25, -0.5, 1]
        let firstCache = SpeechAudioCache(directory: directory)
        #expect(await firstCache.samples(for: key) == nil)
        await firstCache.insert(expected, for: key)
        #expect(await firstCache.samples(for: key) == expected)

        let relaunchedCache = SpeechAudioCache(directory: directory)
        #expect(await relaunchedCache.samples(for: key) == expected)

        let nextPipelineKey = SpeechAudioCacheKey(
            text: "hello",
            language: "en-US",
            voiceID: "F1-speed-1.00",
            pipelineVersion: "future-pipeline"
        )
        #expect(nextPipelineKey.fileName != key.fileName)
    }

    @Test("语音缓存只接收长度受限的单词发音")
    func pronunciationCachePolicy() {
        #expect(SpeechAudioCachePolicy.shouldCache(text: "hello", purpose: .pronunciation))
        #expect(!SpeechAudioCachePolicy.shouldCache(text: "hello", purpose: .general))
        #expect(
            !SpeechAudioCachePolicy.shouldCache(
                text: String(repeating: "a", count: 129),
                purpose: .pronunciation
            )
        )
    }

    @Test("随包模型只有被选中且预热完成才算激活")
    func bundledModelStatusSemantics() {
        let loading = SpeechSynthesisEngineStatus(
            phase: .loading,
            bundledModelBytes: 300,
            selectedEngine: .supertonic3,
            isBundledModelAvailable: true
        )
        let ready = SpeechSynthesisEngineStatus(
            phase: .ready,
            bundledModelBytes: 300,
            selectedEngine: .supertonic3,
            isBundledModelAvailable: true
        )
        let system = SpeechSynthesisEngineStatus(
            phase: .available,
            bundledModelBytes: 300,
            selectedEngine: .system,
            isBundledModelAvailable: true
        )
        #expect(loading.isBusy)
        #expect(!loading.isBundledEngineActive)
        #expect(ready.isBundledEngineActive)
        #expect(!system.isBundledEngineActive)
    }
}
