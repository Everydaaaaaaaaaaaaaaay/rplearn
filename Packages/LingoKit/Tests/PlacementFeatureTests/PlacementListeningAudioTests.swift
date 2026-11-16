import SpeechKit
import Testing
@testable import PlacementFeature

@Suite("校准听力播放顺序")
@MainActor
struct PlacementListeningAudioTests {
    @Test("第一遍只读材料，第二遍材料结束并停顿后才读题干")
    func questionIsSpokenOnlyAfterSecondPassage() {
        let passage = "The book swap will start after lunch."
        let question = "When will the book swap start?"
        #expect(PlacementListeningAudioPlayer.segments(text: passage, question: question, completedPlays: 0)
                == [.init(text: passage)])
        #expect(PlacementListeningAudioPlayer.segments(text: passage, question: question, completedPlays: 1)
                == [.init(text: passage, pauseAfterMs: 3000), .init(text: "Question: " + question)])
    }

    @Test("中文操作提示不混入英文听力")
    func chineseInstructionsAreNotSpoken() {
        #expect(PlacementListeningAudioPlayer.segments(text: "Listen carefully.", question: "What time? 请选出答案。", completedPlays: 1)
                == [.init(text: "Listen carefully.")])
    }
}
