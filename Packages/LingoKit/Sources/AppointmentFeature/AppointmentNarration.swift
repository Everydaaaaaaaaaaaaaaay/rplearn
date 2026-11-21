import BackendKit
import SpeechKit

enum AppointmentNarration {
    static func request(for beat: BackendAppointmentBeat, characterName: String,
                        characterRequest: SpeechRequest?) -> SpeechRequest {
        if beat.speaker == "character" {
            return characterRequest ?? StoryVoiceCasting.request(text: beat.english, speaker: characterName)
        }
        return StoryVoiceCasting.request(text: beat.english, speaker: "旁白")
    }
}
