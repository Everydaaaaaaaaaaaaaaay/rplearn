import AVFoundation
import Foundation
import Testing
import StoryEngine
@testable import StoryFeature
@testable import SpeechKit

@Suite("剧情语音演绎")
struct SpeechDeliveryTests {
    private func episode() throws -> StoryEpisode {
        let url = try #require(Bundle.main.url(forResource: "departures_london_v1", withExtension: "json"))
        return try StoryEpisode.load(data: Data(contentsOf: url))
    }

    @Test("已登记的剧情方向保持原文、音色与分支恢复确定性")
    func sceneDirection() throws {
        let story = try episode()
        #expect(story.nodes.filter { $0.speech != nil }.count == 11)
        for node in story.nodes {
            let plain = LondonEpisodeNarration.request(for: node, variant: .original)
            let directed = LondonEpisodeNarration.request(for: node)
            #expect(plain.text == node.text && directed.text == node.text)
            #expect(plain.voiceHint == directed.voiceHint)
            #expect(Supertonic3VoiceCatalog.profile(for: plain).voiceID == Supertonic3VoiceCatalog.profile(for: directed).voiceID)
            #expect(directed == LondonEpisodeNarration.request(for: try #require(story.node(node.id))))
            let untagged = directed.synthesisSegments.map(\.text).joined(separator: " ")
                .replacingOccurrences(of: "<breath> ", with: "")
            #expect(untagged == node.text)
            if node.speech == nil { #expect(directed.delivery == nil) }
        }
        let breath = LondonEpisodeNarration.request(for: try #require(story.node("two_ways")))
        #expect(breath.voiceHint?.supertonicVoice == .m5)
        #expect(breath.synthesisSegments[0].text.hasPrefix("<breath> "))
        let narrator = LondonEpisodeNarration.request(for: try #require(story.node("silence_part2")))
        #expect(narrator.delivery?.expression == nil)
        #expect(narrator.delivery?.trailingPause == 0.55)
    }

    @Test("新故事所有英文配音随包，原文、选角与真实音频能解码")
    @MainActor func preparedCollection() throws {
        let library = try #require(StoryVoiceLibrary.bundled)
        let catalogURL = try #require(Bundle.main.url(forResource: "departures_catalog", withExtension: "json"))
        let file = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let chapters = try #require(file["chapters"] as? [[String: String]])
        for chapter in chapters {
            let resource = try #require(chapter["id"])
            let url = try #require(Bundle.main.url(forResource: resource, withExtension: "json"))
            let episode = try StoryEpisode.load(data: Data(contentsOf: url))
            for node in episode.nodes where node.choices == nil && node.speaker != "你" {
                let clip = try #require(library.clip(story: episode.id, node: node.id, speaker: node.speaker, text: node.text))
                let decoded = try AVAudioPlayer(contentsOf: clip.url)
                #expect(abs(decoded.duration - clip.seconds) < 0.1)
                #expect(library.request(story: episode.id, node: node.id, speaker: node.speaker, text: node.text)?.voiceHint?.supertonicVoice
                        == LondonEpisodeNarration.request(for: node).voiceHint?.supertonicVoice)
            }
        }
    }

    @Test("精确停顿只切完整句子，错误锚点不吞字")
    func segmentation() {
        let text = "A small beginning. One page, no questions afterwards."
        let request = SpeechRequest(text: text, purpose: .characterDialogue,
                                    delivery: SpeechDelivery(pauseAfter: "A small beginning.", pauseDuration: 0.18))
        #expect(request.synthesisSegments.count == 2)
        #expect(request.synthesisSegments[0].silenceAfter == 0.18)
        #expect(request.synthesisSegments.map(\.text).joined(separator: " ") == text)
        for anchor in ["absent.", "A small", text, ""] {
            let invalid = SpeechRequest(text: text, purpose: .characterDialogue,
                                        delivery: SpeechDelivery(pauseAfter: anchor, pauseDuration: 0.2))
            #expect(invalid.synthesisSegments == [SpeechSynthesisSegment(text: text, silenceAfter: 0)])
        }
    }

    @Test("字典无戏剧效果，缓存区分语速、表达和停顿，异常数值安全收敛")
    func isolationAndCache() {
        let cue = SpeechDelivery(speedMultiplier: 0.95, leadingPause: 0.2, expression: .sigh)
        let word = SpeechRequest(text: "hello", purpose: .pronunciation, delivery: cue)
        #expect(word.narrativeDelivery == nil)
        #expect(word.synthesisSegments[0].text == "hello")
        let cues: [SpeechDelivery?] = [nil, cue, SpeechDelivery(expression: .breath),
            SpeechDelivery(leadingPause: 0.2), SpeechDelivery(trailingPause: 0.2),
            SpeechDelivery(pauseAfter: "Hello.", pauseDuration: 0.2),
            SpeechDelivery(speedMultiplier: 1.001), SpeechDelivery(speedMultiplier: 1.002)]
        let keys = cues.map { SpeechRequest(text: "Hello. Again.", purpose: .characterDialogue, delivery: $0).deliveryCacheIdentity }
        #expect(Set(keys).count == keys.count)
        let invalid = SpeechDelivery(speedMultiplier: .nan, leadingPause: -.infinity, trailingPause: 99)
        #expect(invalid.speedMultiplier == 1 && invalid.leadingPause == 0 && invalid.trailingPause == 1.2)
    }

    @Test("剧本拒绝错位停顿、给旁白加角色呼吸和越界参数，旧剧本仍可加载")
    func scriptValidation() throws {
        let url = try #require(Bundle.main.url(forResource: "departures_london_v1", withExtension: "json"))
        let original = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for mutation in ["anchor", "speed", "narrator"] {
            var object = original
            var nodes = try #require(object["nodes"] as? [[String: Any]])
            let i = try #require(nodes.firstIndex { $0["id"] as? String == (mutation == "narrator" ? "silence" : "small") })
            var cue = try #require(nodes[i]["speech"] as? [String: Any])
            if mutation == "anchor" { cue["pauseAfter"] = "Missing sentence." }
            if mutation == "speed" { cue["speed"] = 5 }
            if mutation == "narrator" { cue["expression"] = "breath" }
            nodes[i]["speech"] = cue; object["nodes"] = nodes
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try StoryEpisode.load(data: data) }
        }
        var legacy = original
        var nodes = try #require(legacy["nodes"] as? [[String: Any]])
        for i in nodes.indices { nodes[i].removeValue(forKey: "speech") }
        legacy["nodes"] = nodes
        #expect(try StoryEpisode.load(data: JSONSerialization.data(withJSONObject: legacy)).nodes.allSatisfy { $0.speech == nil })
    }
}
