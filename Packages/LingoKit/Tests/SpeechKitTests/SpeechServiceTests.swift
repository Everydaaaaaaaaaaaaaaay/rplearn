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

    @Test("退出首次播放所在的聊天后，仍只对标准音提示一次")
    func upgradePromptPolicy() {
        #expect(
            VoiceUpgradePromptPolicy.shouldPresent(
                isSuppressed: false,
                hasPresented: false,
                isOnboarding: false,
                quality: .standard
            )
        )
        #expect(
            !VoiceUpgradePromptPolicy.shouldPresent(
                isSuppressed: false,
                hasPresented: true,
                isOnboarding: false,
                quality: .standard
            )
        )
        #expect(
            !VoiceUpgradePromptPolicy.shouldPresent(
                isSuppressed: true,
                hasPresented: false,
                isOnboarding: false,
                quality: .standard
            )
        )
        #expect(
            !VoiceUpgradePromptPolicy.shouldPresent(
                isSuppressed: false,
                hasPresented: false,
                isOnboarding: false,
                quality: .enhanced
            )
        )
    }

    @Test("已关闭提醒时不读取系统语音库")
    func suppressedPromptSkipsQualityLookup() {
        var didReadQuality = false

        let shouldPresent = VoiceUpgradePromptPolicy.shouldPresent(
            isSuppressed: true,
            hasPresented: false,
            isOnboarding: false,
            quality: {
                didReadQuality = true
                return .standard
            }()
        )
        #expect(!shouldPresent)
        #expect(!didReadQuality)
    }

    @Test("Pocket 音色按角色稳定选择并区分英美男女声")
    func pocketVoiceSelection() {
        let britishMale = SpeechVoiceHint(
            stableID: "oliver",
            gender: "male",
            nationality: "British"
        )
        let americanFemale = SpeechVoiceHint(
            stableID: "casey",
            gender: "female",
            nationality: "American"
        )

        let first = PocketTTSVoiceCatalog.voiceID(language: "en-GB", hint: britishMale)
        let second = PocketTTSVoiceCatalog.voiceID(language: "en-GB", hint: britishMale)
        #expect(first == second)
        #expect(["peter_yearsley", "stuart_bell"].contains(first))
        #expect(PocketTTSVoiceCatalog.voiceID(language: "en-US", hint: americanFemale) == "mary")
        #expect(PocketTTSAssetSelection.voiceIDs.contains(first))
    }

    @Test("TTS 引擎默认值、持久化和旧设置迁移保持稳定")
    func voiceEnginePreferences() {
        let suiteName = "SpeechServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(VoiceEnginePreferences.synthesisEngine(defaults: defaults) == .pocketTTS)

        VoiceEnginePreferences.setSynthesisEngine(.system, defaults: defaults)
        #expect(VoiceEnginePreferences.synthesisEngine(defaults: defaults) == .system)

        defaults.removeObject(forKey: VoiceEnginePreferences.synthesisEngineKey)
        defaults.set(true, forKey: "lingotrip.pocketTTS.enabled")
        #expect(VoiceEnginePreferences.synthesisEngine(defaults: defaults) == .pocketTTS)
    }

    @Test("试听请求可以临时覆盖全局 TTS 引擎")
    func speechRequestEngineOverride() {
        let request = SpeechRequest(text: "Hello", engine: .system)
        #expect(request.engine == .system)
    }

    @Test("安装资源包含完整 Pocket TTS 关键权重")
    func bundledPocketModelsAreComplete() throws {
        let root = Bundle.main.bundleURL
            .appendingPathComponent("LingoKit_SpeechKit.bundle", isDirectory: true)
            .appendingPathComponent("PocketTTS/Models/pocket-tts/v2.1/english", isDirectory: true)
        let weights: [String: Int] = [
            "cond_prefill.mlmodelc/weights/weight.bin": 133_237_248,
            "flow_decoder_fused.mlmodelc/weights/weight.bin": 19_012_608,
            "flowlm_stepv2.mlmodelc/weights/weight.bin": 76_809_280,
            "mimi_decoder.mlmodelc/weights/weight.bin": 41_768_256,
            "constants_bin/text_embed_table.bin": 16_388_096,
        ]

        for (relativePath, expectedSize) in weights {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: root.appendingPathComponent(relativePath).path
            )
            #expect(attributes[.size] as? Int == expectedSize)
        }
    }

    @Test("运行时模型校验允许安装器加入非关键文件")
    func runtimeModelValidationAllowsInstallerMetadata() async throws {
        let fileManager = FileManager.default
        let modelDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PocketTTSValidation-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: modelDirectory) }
        let root = modelDirectory.appendingPathComponent(
            "Models/pocket-tts/v2.1/english",
            isDirectory: true
        )

        let requiredFiles: [String: Int64] = [
            "cond_prefill.mlmodelc/weights/weight.bin": 133_237_248,
            "flow_decoder_fused.mlmodelc/weights/weight.bin": 19_012_608,
            "flowlm_stepv2.mlmodelc/weights/weight.bin": 76_809_280,
            "mimi_decoder.mlmodelc/weights/weight.bin": 41_768_256,
            "constants_bin/text_embed_table.bin": 16_388_096,
        ]
        for (relativePath, byteCount) in requiredFiles {
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

        let constants = root.appendingPathComponent("constants_bin", isDirectory: true)
        let voiceIDs = [
            "alba", "anna", "bill_boerst", "mary", "michael", "peter_yearsley",
            "stuart_bell",
        ]
        for name in ["tokenizer.model", "bos_emb.bin"]
            + voiceIDs.map({ "\($0).safetensors" }) {
            let url = constants.appendingPathComponent(name)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            #expect(fileManager.createFile(atPath: url.path, contents: Data([0])))
        }

        let installerMetadata = root.appendingPathComponent("installer-metadata.plist")
        #expect(fileManager.createFile(atPath: installerMetadata.path, contents: Data([0])))

        let service = AdaptiveSpeechService(
            audioSession: AudioSessionCoordinator(),
            modelDirectory: modelDirectory
        )
        let status = await service.synthesisEngineStatus()
        #expect(status.phase == BundledSpeechModelPhase.available)
        #expect(status.isBundledModelAvailable)
    }

    @Test("Pocket 流播只等待短缓冲并在收尾时立即开播")
    func pocketPlaybackBufferPolicy() {
        let sampleRate = 100.0

        #expect(
            !PocketTTSPlaybackBufferPolicy.shouldStart(
                bufferedSampleCount: 23,
                sampleRate: sampleRate,
                producerDidFinish: false
            )
        )
        #expect(
            PocketTTSPlaybackBufferPolicy.shouldStart(
                bufferedSampleCount: 24,
                sampleRate: sampleRate,
                producerDidFinish: false
            )
        )
        #expect(
            PocketTTSPlaybackBufferPolicy.shouldStart(
                bufferedSampleCount: 1,
                sampleRate: sampleRate,
                producerDidFinish: true
            )
        )
    }

    @Test("随包模型只有被选中且预热完成才算激活")
    func bundledModelStatusSemantics() {
        let loading = SpeechSynthesisEngineStatus(
            phase: .loading,
            bundledModelBytes: 300,
            selectedEngine: .pocketTTS,
            isBundledModelAvailable: true
        )
        let ready = SpeechSynthesisEngineStatus(
            phase: .ready,
            bundledModelBytes: 300,
            selectedEngine: .pocketTTS,
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
