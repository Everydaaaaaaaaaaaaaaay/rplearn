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
        player.play(segments: Self.segments(text: text, question: question, completedPlays: completedPlays),
                    voice: ListeningVoicePolicy.voice(completedPlays: completedPlays),
                    started: started, completed: completed)
    }

    static func segments(text: String, question: String, completedPlays: Int) -> [ListeningSpeechSegment] {
        if completedPlays == 1, question.contains("?"),
           question.range(of: "\\p{Han}", options: .regularExpression) == nil {
            return [.init(text: text, pauseAfterMs: 3000), .init(text: "Question: " + question)]
        }
        return [.init(text: text)]
    }

    func stop() { player.stop() }
}
