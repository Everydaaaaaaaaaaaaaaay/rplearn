import Foundation
import Testing
@testable import StoryEngine

@MainActor
@Suite("Opening story")
struct OnboardingStoryTests {
    @Test("Three concise routes introduce all companions and finish without a tutorial")
    func branches() throws {
        let url = try #require(Bundle.main.url(forResource: "onboarding_chat", withExtension: "json"))
        let script = try StoryScript.load(from: url)
        var transcripts: Set<String> = []
        for choice in 0..<3 {
            let player = StoryPlayer(script: script)
            var count = 0
            var unlocks: [String] = []
            player.onCompleted = { unlocks = $0 }
            for _ in 0..<40 where !player.isFinished {
                if let options = player.currentChoices {
                    #expect(options.count == 3)
                    player.choose(choice)
                    count += 1
                }
                player.advance()
            }
            #expect(player.isFinished)
            #expect(count == 1)
            #expect(player.history.count <= 13)
            #expect(unlocks == ["character_selection"])
            #expect(Set(player.history.map(\.speaker)) == ["咕咕", "嘎嘎", "Oliver", "Ruby", "Marcus"])
            #expect(player.history.filter { $0.sprite?.hasPrefix("card:") == true }.count == 3)
            for line in player.history where line.speaker == "咕咕" || line.speaker == "嘎嘎" {
                #expect(line.text.contains(line.speaker == "咕咕" ? "咕" : "嘎"))
            }
            for line in player.history where ["Oliver", "Ruby", "Marcus"].contains(line.speaker) {
                #expect(line.text.components(separatedBy: "\n\n").count == 2)
            }
            transcripts.insert(player.history.map(\.text).joined())
        }
        #expect(transcripts.count == 3)
    }
}
