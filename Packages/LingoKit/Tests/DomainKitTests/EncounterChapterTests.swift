import DomainKit
import Foundation
import Testing

@Suite("本地完整相遇剧情")
struct EncounterChapterTests {
    @Test("全部 200 人的 800 条路径与重逢可读取")
    func everyPath() throws {
        let library = try AuthoredEncounterLibrary.bundled()
        #expect(library.entries.count == 200)
        for entry in library.entries.values {
            let opening = try library.chapter(characterID: entry.id, actionID: entry.story.actionId, choices: [])
            #expect(opening.choices.count == 2)
            #expect(opening.titleEnglish?.isEmpty == false)
            for first in 0...1 {
                let middle = try library.chapter(characterID: entry.id, actionID: entry.story.actionId, choices: [first])
                #expect(middle.choices.count == 2)
                for second in 0...1 {
                    let ending = try library.chapter(characterID: entry.id, actionID: entry.story.actionId, choices: [first, second])
                    #expect(ending.choices.isEmpty)
                    #expect(ending.beats.count >= 4)
                }
            }
            let reunion = try library.chapter(characterID: entry.id, actionID: entry.story.actionId, choices: [], reunion: true)
            #expect(reunion.choices.isEmpty)
            #expect(reunion.titleEnglish?.isEmpty == false)
            #expect(reunion.beats != opening.beats)
            #expect(throws: (any Error).self) { try library.chapter(characterID: entry.id, actionID: "missing", choices: []) }
            #expect(throws: (any Error).self) { try library.chapter(characterID: entry.id, actionID: entry.story.actionId, choices: [2]) }
            #expect(throws: (any Error).self) { try library.chapter(characterID: entry.id, actionID: entry.story.actionId, choices: [0, 0, 0]) }
        }
    }

    @Test("损坏的分支不能进入运行库")
    func rejectsBrokenGraph() throws {
        let url = try #require(Bundle.main.url(forResource: "npc-library-v3", withExtension: "json"))
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var entries = try #require(manifest["entries"] as? [[String: Any]])
        var story = try #require(entries[0]["story"] as? [String: Any])
        var nodes = try #require(story["nodes"] as? [[String: Any]])
        let start = try #require(nodes.firstIndex { $0["id"] as? String == "start" })
        var choices = try #require(nodes[start]["choices"] as? [[String: Any]])
        choices[0]["next"] = "bb"
        nodes[start]["choices"] = choices
        story["nodes"] = nodes
        entries[0]["story"] = story
        manifest["entries"] = entries
        let data = try JSONSerialization.data(withJSONObject: manifest)
        #expect(throws: (any Error).self) { try AuthoredEncounterLibrary(data: data) }
    }
}
