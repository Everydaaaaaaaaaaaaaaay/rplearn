import CoreKit
import Foundation
import Testing

@Suite("学习聊天来源协议")
struct LearningChatOriginTests {
    @Test("来源往返与服务端字段一致，不携带客户端分数")
    func roundTrip() throws {
        let cycle = UUID(), user = UUID(), operation = UUID()
        let values: [LearningChatOrigin] = [.user(cycleID: cycle),
            .assistant(cycleID: cycle, userMessageID: user, operationID: operation, fragmentIndex: 1, fragmentCount: 2)]
        for origin in values {
            let json = try origin.encodedJSON()
            #expect(LearningChatOrigin.decode(json: json) == origin)
            let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            #expect(object["cycleId"] as? String == cycle.uuidString.lowercased())
            #expect(object["count"] == nil)
            #expect(object["points"] == nil)
        }
    }
    @Test("分片越界拒绝编码，旧消息缺少来源不会自动补签")
    func malformed() {
        #expect(LearningChatOrigin.decode(json: nil) == nil)
        #expect(LearningChatOrigin.decode(json: "{}") == nil)
        let origin = LearningChatOrigin.assistant(cycleID: UUID(), userMessageID: UUID(), operationID: UUID(), fragmentIndex: 2, fragmentCount: 2)
        #expect(throws: (any Error).self) { try origin.encodedJSON() }
    }
}
