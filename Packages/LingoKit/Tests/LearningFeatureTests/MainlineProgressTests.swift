import BackendKit
import Foundation
import Testing

@Suite("主线服务端状态合同")
struct MainlineProgressTests {
    @Test("只有服务端明确开放或已完成的章节可以进入")
    func failClosed() throws {
        for (state, allowed) in [("available", true), ("completed", true), ("locked", false), ("future-state", false)] {
            let json: [String: Any] = ["storyId": "mainline_capetown", "regionId": "capetown", "sequence": 2,
                                     "requiredStars": 3, "missingStars": 1, "previousStoryId": "mainline_london", "state": state, "lockReason": "stars"]
            let chapter = try JSONDecoder().decode(BackendMainlineProgress.Chapter.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(chapter.canOpen == allowed)
            if state == "locked" { #expect(chapter.statusText == "再获得 1 颗星") }
        }
    }
}
