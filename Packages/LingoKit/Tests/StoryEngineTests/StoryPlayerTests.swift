import Foundation
import Testing
@testable import StoryEngine

@MainActor
@Suite("StoryPlayer")
struct StoryPlayerTests {
    private func makeScript() throws -> StoryScript {
        let json = Data("""
        {
          "id": "t",
          "start": "l1",
          "nodes": [
            {"id":"l1","type":"line","speaker":"A","text":"one","next":"c1"},
            {"id":"c1","type":"choice","options":[
              {"text":"yes","next":"b1","setFlags":{"agreed":true}},
              {"text":"no","next":"b1"}
            ]},
            {"id":"b1","type":"branch","flag":"agreed","ifTrue":"l2","ifFalse":"l3"},
            {"id":"l2","type":"line","speaker":"A","text":"agreed-path","next":"r1"},
            {"id":"l3","type":"line","speaker":"A","text":"refused-path","next":"r1"},
            {"id":"r1","type":"reward","coins":50,"ticket":"universal","next":"l4"},
            {"id":"l4","type":"line","speaker":"B","text":"bye","next":"e1"},
            {"id":"e1","type":"end","unlocks":["next_chapter"]}
          ]
        }
        """.utf8)
        return try StoryScript.load(from: json)
    }

    @Test("台词逐条推进，选项处停下")
    func advanceToChoice() throws {
        let player = StoryPlayer(script: try makeScript())
        player.advance()
        #expect(player.history.map(\.text) == ["one"])
        #expect(player.currentChoices == nil)
        player.advance() // 进入 choice
        #expect(player.currentChoices?.count == 2)
        // 选项期间 advance 无效
        player.advance()
        #expect(player.history.count == 1)
    }

    @Test("选择设置 flag 并走对应分支，奖励回调触发，end 收尾")
    func chooseBranchRewardEnd() throws {
        let player = StoryPlayer(script: try makeScript())
        var rewards: [StoryReward] = []
        var unlocks: [String] = []
        player.onReward = { rewards.append($0) }
        player.onCompleted = { unlocks = $0 }

        player.advance() // one
        player.advance() // choice
        player.choose(0) // agreed
        player.advance() // agreed-path
        #expect(player.history.last?.text == "agreed-path")
        #expect(player.flags["agreed"] == true)

        player.advance() // reward 自动处理 → bye
        #expect(rewards == [StoryReward(coins: 50, ticket: "universal")])
        #expect(player.history.last?.text == "bye")

        player.advance() // end
        #expect(player.isFinished)
        #expect(unlocks == ["next_chapter"])
    }

    @Test("未选 flag 走 ifFalse 分支")
    func falseBranch() throws {
        let player = StoryPlayer(script: try makeScript())
        player.advance()
        player.advance()
        player.choose(1)
        player.advance()
        #expect(player.history.last?.text == "refused-path")
    }

    @Test("skipToNextChoiceOrEnd 快进")
    func skip() throws {
        let player = StoryPlayer(script: try makeScript())
        player.skipToNextChoiceOrEnd()
        #expect(player.currentChoices != nil)
        player.choose(0)
        player.skipToNextChoiceOrEnd()
        #expect(player.isFinished)
        #expect(player.history.map(\.text) == ["one", "agreed-path", "bye"])
    }

    @Test("断点续播：从指定节点恢复")
    func resume() throws {
        let player = StoryPlayer(script: try makeScript(), resumeFrom: "l4", flags: ["agreed": true])
        player.advance()
        #expect(player.history.map(\.text) == ["bye"])
    }
}
