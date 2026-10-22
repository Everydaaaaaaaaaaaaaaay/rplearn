import CoreKit
import Foundation
import SpeechKit

/// Calibration uses the same live, memory-only Supertonic player as lesson listening.
@MainActor
final class PlacementListeningAudioPlayer {
    private let player: ListeningSpeechPlayer
    init(audioSession: AudioSessionCoordinator, speech: any SpeechService) {
        player = ListeningSpeechPlayer(speech: speech, session: audioSession)
    }
    func play(text: String, question: String, completedPlays: Int,
              started: @escaping @MainActor @Sendable () -> Void,
              completed: @escaping @MainActor @Sendable (Bool) -> Void) {
        var segments = [ListeningSpeechSegment(text: text)]
        if question.contains("?"), question.range(of: "\\p{Han}", options: .regularExpression) == nil {
            segments = [.init(text: text, pauseAfterMs: 3000), .init(text: "Question: " + question)]
        }
        player.play(segments: segments, voice: ListeningVoicePolicy.voice(completedPlays: completedPlays),
                    started: started, completed: completed)
    }
    func stop() { player.stop() }
}
