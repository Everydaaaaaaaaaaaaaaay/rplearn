import Foundation
import Testing
@testable import StoryEngine

@MainActor
@Suite("Opening story")
struct OnboardingStoryTests {
    @Test("All 27 combinations finish, introduce both guides and all companions, and recall the initial choice")
    func branches() throws {
        let url = try #require(Bundle.main.url(forResource: "onboarding_chat", withExtension: "json"))
        let script = try StoryScript.load(from: url)
        var transcripts: Set<String> = []
        for first in 0..<3 {
            for second in 0..<3 {
                for third in 0..<3 {
                    let player = StoryPlayer(script: script)
                    let choices = [first, second, third]
                    var choiceCount = 0
                    var unlocks: [String] = []
                    player.onCompleted = { unlocks = $0 }
                    for _ in 0..<80 where !player.isFinished {
                        if let options = player.currentChoices {
                            #expect(options.count == 3)
                            #expect(choiceCount < 3)
                            guard choiceCount < 3 else { return }
                            player.choose(choices[choiceCount])
                            choiceCount += 1
                        }
                        player.advance()
                    }
                    #expect(player.isFinished)
                    #expect(choiceCount == 3)
                    #expect(unlocks == ["character_selection"])
                    #expect(Set(player.history.map(\.speaker)) == ["咕咕", "嘎嘎", "Oliver", "Ruby", "Marcus"])
                    #expect(player.history.filter { $0.sprite?.hasPrefix("card:") == true }.count == 3)
                    let endings = ["地图还在", "你说想先", "说好慢慢"]
                    #expect(player.history.last?.text.hasPrefix(endings[first]) == true)
                    transcripts.insert(player.history.map(\.text).joined())
                }
            }
        }
        #expect(transcripts.count == 27)
    }
}
