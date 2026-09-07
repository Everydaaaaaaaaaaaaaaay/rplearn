import SpeechKit
import StoryEngine

/// The preview and its audio audition share casting and direction resolution.
/// Scene/branch node metadata is the context; resuming needs no hidden mood state.
enum LondonEpisodeNarration {
    enum Variant: String, CaseIterable { case original, rhythm, expressive }

    static func request(for node: StoryEpisode.Node, variant: Variant = .expressive) -> SpeechRequest {
        let voices: [String: SupertonicVoice] = [
            "Oliver": .m5, "Nora": .f5, "旁白": .f5, "出发之后": .f5,
            "Ruby": .f3, "Marcus": .m3, "Amara": .f4, "Mei": .f1,
            "Amina": .f1, "Jonas": .m4, "Elena": .f2, "Niamh": .f4,
            "Isla": .f1, "Noah": .m1, "Ruth": .f4, "Hana": .f2,
            "Peter": .m4, "Wanjiku": .f2, "Zuri": .f1, "Maya": .f3,
            "Sam": .m1, "Tahlia": .f3, "Calvin": .m2, "June": .f4,
            "Leah": .f2, "Aaliyah": .f4, "Uncle Tan": .m4
        ]
        let voice = voices[node.speaker] ?? .f5
        let oliver = node.speaker == "Oliver"
        let identity = oliver ? "london.oliver" : node.speaker == "Nora" ? "london.nora" : "departures.\(node.speaker)"
        let delivery: SpeechDelivery?
        if variant != .original, let cue = node.speech {
            delivery = SpeechDelivery(
                speedMultiplier: Float(cue.speed), leadingPause: cue.before, trailingPause: cue.after,
                expression: variant == .expressive ? cue.expression.flatMap { SpeechDelivery.Expression(rawValue: $0.rawValue) } : nil,
                pauseAfter: cue.pauseAfter, pauseDuration: cue.pauseDuration ?? 0
            )
        } else { delivery = nil }
        return SpeechRequest(text: node.text, language: "en", purpose: .characterDialogue,
                             voiceHint: SpeechVoiceHint(stableID: identity, gender: voice.rawValue.hasPrefix("M") ? "male" : "female",
                                                       supertonicVoice: voice),
                             engine: .supertonic3, delivery: delivery)
    }
}
