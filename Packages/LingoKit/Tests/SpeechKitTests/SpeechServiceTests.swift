import AVFoundation
import Testing
@testable import SpeechKit

@Suite("AppleTTS 语音选择")
struct SpeechServiceTests {
    typealias Candidate = (language: String, qualityRank: Int, name: String)

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

    @Test("Pocket 下载过滤掉未使用的大模型和音色")
    func pocketAssetSelection() {
        #expect(
            PocketTTSAssetSelection.shouldSkip(
                remotePath: "v2.1/english/flowlm_step.mlmodelc/weights/weight.bin"
            )
        )
        #expect(
            PocketTTSAssetSelection.shouldSkip(
                remotePath: "v2.1/english/pocket_state.mlmodelc/weights/weight.bin"
            )
        )
        #expect(
            PocketTTSAssetSelection.shouldSkip(
                remotePath: "v2.1/english/constants_bin/cosette.safetensors"
            )
        )
        #expect(
            !PocketTTSAssetSelection.shouldSkip(
                remotePath: "v2.1/english/flowlm_stepv2.mlmodelc/weights/weight.bin"
            )
        )
        #expect(
            !PocketTTSAssetSelection.shouldSkip(
                remotePath: "v2.1/english/constants_bin/mary.safetensors"
            )
        )
        #expect(
            !PocketTTSAssetSelection.shouldSkip(
                remotePath: "v2.1/english/constants_bin/text_embed_table.bin"
            )
        )
    }

    @Test("离线模型只有启用且预热完成才算激活")
    func offlineModelStatusSemantics() {
        let loading = OfflineSpeechModelStatus(
            phase: .loading,
            installedBytes: 300,
            expectedDownloadBytes: 400,
            isEnabled: true,
            isInstalled: true
        )
        let ready = OfflineSpeechModelStatus(
            phase: .ready,
            installedBytes: 300,
            expectedDownloadBytes: 400,
            isEnabled: true,
            isInstalled: true
        )
        let disabled = OfflineSpeechModelStatus(
            phase: .installed,
            installedBytes: 300,
            expectedDownloadBytes: 400,
            isEnabled: false,
            isInstalled: true
        )

        #expect(loading.isBusy)
        #expect(!loading.isActive)
        #expect(ready.isActive)
        #expect(!disabled.isActive)
    }
}
