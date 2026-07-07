import Foundation
import Testing
@testable import StoryEngine

@Suite("StoryScript 校验")
struct StoryScriptTests {
    private func makeJSON(_ nodes: String) -> Data {
        Data("""
        {"id": "t", "start": "a", "nodes": [\(nodes)]}
        """.utf8)
    }

    @Test("合法脚本可加载")
    func validScript() throws {
        let json = makeJSON("""
        {"id":"a","type":"line","speaker":"S","text":"hi","next":"b"},
        {"id":"b","type":"end"}
        """)
        let script = try StoryScript.load(from: json)
        #expect(script.nodes.count == 2)
    }

    @Test("悬空引用报错")
    func danglingReference() {
        let json = makeJSON("""
        {"id":"a","type":"line","speaker":"S","text":"hi","next":"missing"}
        """)
        #expect(throws: StoryScript.ValidationError.danglingReference(from: "a", to: "missing")) {
            try StoryScript.load(from: json)
        }
    }

    @Test("不可达节点报错")
    func unreachableNode() {
        let json = makeJSON("""
        {"id":"a","type":"end"},
        {"id":"orphan","type":"end"}
        """)
        #expect(throws: StoryScript.ValidationError.unreachableNodes(["orphan"])) {
            try StoryScript.load(from: json)
        }
    }

    @Test("start 缺失报错")
    func missingStart() {
        let json = Data(#"{"id":"t","start":"nope","nodes":[{"id":"a","type":"end"}]}"#.utf8)
        #expect(throws: StoryScript.ValidationError.missingStart("nope")) {
            try StoryScript.load(from: json)
        }
    }

    @Test("空选项报错")
    func emptyChoice() {
        let json = makeJSON("""
        {"id":"a","type":"choice","options":[]}
        """)
        #expect(throws: StoryScript.ValidationError.emptyChoice("a")) {
            try StoryScript.load(from: json)
        }
    }

    @Test("随包主线脚本可加载且含奖励节点", arguments: ["mainline_london", "mainline_melbourne", "mainline_newyork"])
    func bundledMainlineScripts(storyID: String) throws {
        let url = try #require(Bundle.main.url(forResource: storyID, withExtension: "json"))
        let script = try StoryScript.load(from: url)
        #expect(script.id == storyID)
        let hasReward = script.nodes.values.contains { node in
            if case .reward(let reward, _) = node.payload { return reward.coins > 0 }
            return false
        }
        #expect(hasReward)
        let hasChoice = script.nodes.values.contains { node in
            if case .choice = node.payload { return true }
            return false
        }
        #expect(hasChoice)
    }

    @Test("随包 onboarding_chat.json 可加载且以 end 结束")
    func bundledOnboardingScript() throws {
        let url = try #require(Bundle.main.url(forResource: "onboarding_chat", withExtension: "json"))
        let script = try StoryScript.load(from: url)
        #expect(script.id == "onboarding_chat")
        #expect(script.nodes.values.contains { node in
            if case .end = node.payload { return true }
            return false
        })
        // 介绍了三位主角色
        let allText = script.nodes.values.compactMap { node -> String? in
            if case .line(_, let text, _, _, _) = node.payload { return text }
            return nil
        }.joined()
        #expect(allText.contains("Oliver"))
        #expect(allText.contains("Ruby"))
        #expect(allText.contains("Marcus"))
    }
}
