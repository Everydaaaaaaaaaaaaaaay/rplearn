import Foundation
import Testing
@testable import DomainKit
@testable import StoryEngine

@Suite("StoryScript 校验")
struct StoryScriptTests {
    private func makeJSON(_ nodes: String) -> Data {
        Data("""
        {"id": "t", "start": "a", "nodes": [\(nodes)]}
        """.utf8)
    }

    @Test("重复节点返回校验错误，不因 Dictionary 初始化直接崩溃")
    func duplicateNode() {
        #expect(throws: StoryScript.ValidationError.duplicateNode("a")) {
            try StoryScript.load(from: makeJSON(#"{"id":"a","type":"end"},{"id":"a","type":"end"}"#))
        }
    }

    @Test("纯自动分支循环在加载时拒绝，避免主线程死循环")
    func automaticCycle() {
        #expect(throws: StoryScript.ValidationError.automaticCycle("a")) {
            try StoryScript.load(from: makeJSON(#"{"id":"a","type":"branch","flag":"x","ifTrue":"a","ifFalse":"a"}"#))
        }
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
