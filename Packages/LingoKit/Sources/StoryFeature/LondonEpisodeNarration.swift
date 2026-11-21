import SpeechKit
import StoryEngine

/// The preview and its audio audition share casting and direction resolution.
/// Scene/branch node metadata is the context; resuming needs no hidden mood state.
enum LondonEpisodeNarration {
    enum Variant: String, CaseIterable { case original, rhythm, expressive }

    static func request(for node: StoryEpisode.Node, variant: Variant = .expressive) -> SpeechRequest {
        let profile = StoryVoiceCasting.profile(speaker: node.speaker)
        let baseRate = profile?.rate ?? 1
        let delivery: SpeechDelivery?
        if variant != .original, let cue = node.speech {
            let trailingPause = StoryVoiceCasting.isNarrator(node.speaker) || node.ending == true
                ? cue.after : min(cue.after, profile?.pauseAfter ?? cue.after)
            delivery = SpeechDelivery(
                speedMultiplier: baseRate * Float(cue.speed), leadingPause: cue.before, trailingPause: trailingPause,
                expression: variant == .expressive ? cue.expression.flatMap { SpeechDelivery.Expression(rawValue: $0.rawValue) } : nil,
                pauseAfter: cue.pauseAfter, pauseDuration: cue.pauseDuration ?? 0
            )
        } else { delivery = SpeechDelivery(speedMultiplier: baseRate, trailingPause: profile?.pauseAfter ?? 0.3) }
        return SpeechRequest(text: node.text, language: profile?.language ?? "en-US", purpose: .characterDialogue,
                             voiceHint: StoryVoiceCasting.hint(speaker: node.speaker),
                             engine: .supertonic3, delivery: delivery)
    }
}
