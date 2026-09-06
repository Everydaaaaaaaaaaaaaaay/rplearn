import SpeechKit
import StoryEngine

/// The preview and its audio audition share casting and direction resolution.
/// Scene/branch node metadata is the context; resuming needs no hidden mood state.
enum LondonEpisodeNarration {
    enum Variant: String, CaseIterable { case original, rhythm, expressive }

    static func request(for node: StoryEpisode.Node, variant: Variant = .expressive) -> SpeechRequest {
        let oliver = node.speaker == "Oliver"
        let identity = oliver ? "london.oliver" : node.speaker == "Nora" ? "london.nora" : "london.narrator"
        let delivery: SpeechDelivery?
        if variant != .original, let cue = node.speech {
            delivery = SpeechDelivery(
                speedMultiplier: Float(cue.speed), leadingPause: cue.before, trailingPause: cue.after,
                expression: variant == .expressive ? cue.expression.flatMap { SpeechDelivery.Expression(rawValue: $0.rawValue) } : nil,
                pauseAfter: cue.pauseAfter, pauseDuration: cue.pauseDuration ?? 0
            )
        } else { delivery = nil }
        return SpeechRequest(text: node.text, language: "en", purpose: .characterDialogue,
                             voiceHint: SpeechVoiceHint(stableID: identity, gender: oliver ? "male" : "female",
                                                       supertonicVoice: oliver ? .m5 : .f5),
                             engine: .supertonic3, delivery: delivery)
    }
}
