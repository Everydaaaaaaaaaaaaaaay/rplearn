import DomainKit
import Foundation
import Testing

@Suite("相遇分支完整性")
struct SocialEncounterPlanTests {
    private func fixture() -> [String: Any] {
        let reply: [String: Any] = ["english": "Hello there.", "chinese": "你好。", "acceptsContact": false]
        func choice(_ text: String) -> [String: String] { ["english": text, "chinese": "你好。"] }
        let endings: [[String: Any]] = [
            ["intent": "invite", "choice": choice("Keep in touch?"), "reply": reply],
            ["intent": "leave", "choice": choice("Goodbye!"), "reply": reply]
        ]
        return ["opening": reply, "branches": [
            ["choice": choice("How is your day?"), "reply": reply, "endings": endings],
            ["choice": choice("Nice weather?"), "reply": reply, "endings": endings]
        ]]
    }
    private func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
    @Test("完整分支可解码；截断、缺失和非法授予好友资格不能进入交互")
    func validatesWholeTree() throws {
        let valid = fixture()
        #expect(try SocialEncounterPlan.decode(json(valid)).branches.count == 2)
        #expect(throws: (any Error).self) { try SocialEncounterPlan.decode("{\"opening\":") }
        var missing = valid
        missing["branches"] = []
        #expect(throws: (any Error).self) { try SocialEncounterPlan.decode(json(missing)) }
        var illegal = valid
        illegal["opening"] = ["english": "Hello.", "chinese": "你好。", "acceptsContact": true]
        #expect(throws: (any Error).self) { try SocialEncounterPlan.decode(json(illegal)) }
        var branches = valid["branches"] as! [[String: Any]]
        var endings = branches[1]["endings"] as! [[String: Any]]
        endings[1]["reply"] = ["english": "Goodbye.", "chinese": "再见。", "acceptsContact": true]
        branches[1]["endings"] = endings
        illegal = valid
        illegal["branches"] = branches
        #expect(throws: (any Error).self) { try SocialEncounterPlan.decode(json(illegal)) }
    }
}
