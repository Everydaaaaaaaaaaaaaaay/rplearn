import BackendKit
import Foundation
import SpeechKit
import Testing
@testable import AppointmentFeature

@Suite("约定剧情角色与旁白选角")
struct AppointmentNarrationTests {
    private func beat(speaker: String) throws -> BackendAppointmentBeat {
        let data = try JSONSerialization.data(withJSONObject: ["speaker": speaker,
            "english": "We can take the shorter walk.", "chinese": "我们可以走短一点的路线。"])
        return try JSONDecoder().decode(BackendAppointmentBeat.self, from: data)
    }

    @Test("角色台词与旁白走独立请求，支持全名、改名和已有角色声线")
    func speakerIdentity() throws {
        for (name, voice) in [("Ruby Walker", SupertonicVoice.f3), ("Oliver Bennett", .m5), ("Marcus Rivera", .m3)] {
            let line = try beat(speaker: "character")
            let request = AppointmentNarration.request(for: line, characterName: name, characterRequest: nil)
            #expect(request.voiceHint?.supertonicVoice == voice)
            #expect(request.voiceHint?.stableID != StoryVoiceCasting.narratorID)
            #expect(request.purpose == .characterDialogue)
        }
        let ruby = StoryVoiceCasting.request(text: try beat(speaker: "character").english, speaker: "Ruby")
        let renamed = AppointmentNarration.request(for: try beat(speaker: "character"), characterName: "露比", characterRequest: ruby)
        #expect(renamed == ruby)
        let narration = AppointmentNarration.request(for: try beat(speaker: "narrator"), characterName: "Ruby", characterRequest: ruby)
        #expect(narration.voiceHint?.supertonicVoice == .f5)
        #expect(narration.voiceHint?.stableID == StoryVoiceCasting.narratorID)
        let custom = StoryVoiceCasting.request(text: "Hello.", speaker: "Another friend",
            fallback: SpeechVoiceHint(stableID: "friend-id", gender: "male", supertonicVoice: .m2), language: "en-NZ")
        #expect(custom.voiceHint?.supertonicVoice == .m2)
        #expect(custom.language == "en-NZ")
    }
}
