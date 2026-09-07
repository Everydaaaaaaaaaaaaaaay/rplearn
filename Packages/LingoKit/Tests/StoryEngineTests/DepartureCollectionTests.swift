import Foundation
import Testing
import UIKit
import DomainKit
@testable import StoryEngine

@Suite("出发之后全篇分支与续读") @MainActor
struct DepartureCollectionTests {
    struct Catalog: Decodable {
        struct Chapter: Decodable { let id: String; let kind: String; let city: String }
        let chapters: [Chapter]
    }
    private func catalog() throws -> Catalog {
        let url = try #require(Bundle.main.url(forResource: "departures_catalog", withExtension: "json"))
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    @Test("五站主线与十五城完整登记；脚本及引用画面可载入")
    func resources() throws {
        let chapters = try catalog().chapters
        #expect(chapters.filter { $0.kind == "mainline" }.count == 5)
        #expect(chapters.filter { $0.kind == "city" }.count == 15)
        #expect(Set(chapters.map(\.id)).count == chapters.count)
        #expect(Set(chapters.filter { $0.kind == "city" }.map(\.city)).count == 15)
        for chapter in chapters {
            let url = try #require(Bundle.main.url(forResource: chapter.id, withExtension: "json"))
            let episode = try StoryEpisode.load(data: Data(contentsOf: url))
            #expect(episode.maxDialogueCharacters == 65)
            for name in episode.assetNames {
                #expect(Bundle.main.url(forResource: name, withExtension: "png") != nil
                    || Bundle.main.url(forResource: name, withExtension: "jpg") != nil
                    || UIImage(named: name) != nil)
            }
        }
    }

    @Test("正式目录与脚本一致；旧叙事退包，奖励标识保持唯一")
    func formalCatalogAndRetirement() throws {
        let chapters = try catalog().chapters
        let ids = Set(chapters.map(\.id))
        #expect(ids == Set(MainlineCatalog.chapters.map(\.storyID) + CityStoryCatalog.chapters.map(\.storyID)))
        #expect(Set(DepartureStoryIdentity.rewardIDs.keys) == ids)
        #expect(Set(DepartureStoryIdentity.rewardIDs.values).count == ids.count)
        for legacyID in DepartureStoryIdentity.rewardIDs.values {
            #expect(Bundle.main.url(forResource: legacyID, withExtension: "json") == nil)
        }
    }

    @Test("所有选择组合走到结尾；逐页恢复不换分支、不丢台词或画面")
    func allPathsAndCheckpoints() throws {
        for chapter in try catalog().chapters {
            let url = try #require(Bundle.main.url(forResource: chapter.id, withExtension: "json"))
            let episode = try StoryEpisode.load(data: Data(contentsOf: url))
            let choices = episode.nodes.filter { $0.choices != nil }
            #expect((1...2).contains(choices.count))
            var reached: Set<String> = []
            for mask in 0..<(1 << choices.count) {
                var session = EpisodeSession(episode: episode)
                for _ in 0...episode.nodes.count {
                    reached.insert(session.nodeID)
                    if let variant = session.current.shotBranch {
                        let value = try #require(session.flags[variant.flag])
                        #expect(session.shotID == (value ? variant.yes : variant.no))
                    }
                    let saved = try JSONEncoder().encode(session.checkpoint)
                    let restored = EpisodeSession(episode: episode, saved: saved)
                    #expect(restored.checkpoint == session.checkpoint)
                    #expect(restored.history == session.history)
                    #expect(restored.shot == session.shot)
                    let synced = try EpisodeSession(episode: episode, nodeID: session.nodeID, flags: session.flags, completed: false)
                    #expect(synced.checkpoint == session.checkpoint)
                    #expect(synced.history == session.history)
                    #expect(synced.shot == session.shot)
                    if session.isFinished {
                        let completed = try EpisodeSession(episode: episode, nodeID: nil, flags: session.flags, completed: true)
                        #expect(completed.checkpoint == session.checkpoint)
                        #expect(completed.decisionRecords.map(\.choice) == session.decisionRecords.map(\.choice))
                    }
                    if session.isFinished { break }
                    if let options = session.current.choices {
                        let index = try #require(choices.firstIndex { $0.id == session.nodeID })
                        let choice = options[(mask >> index) & 1]
                        #expect(choice.review != nil)
                        session.choose(choice.id)
                    } else { let advanced = session.advance(); #expect(advanced) }
                }
                #expect(session.isFinished)
                #expect(session.decisionRecords.count == choices.count)
                #expect(session.decisionRecords.allSatisfy { $0.outcome != nil })
            }
            #expect(reached == Set(episode.nodes.map(\.id)))
        }
    }

    @Test("同步断点缺少选择、目标失效或含未知标志时拒绝恢复")
    func invalidSyncedProgress() throws {
        let url = try #require(Bundle.main.url(forResource: "departures_city_london_v1", withExtension: "json"))
        let episode = try StoryEpisode.load(data: Data(contentsOf: url))
        #expect(throws: StoryEpisode.ValidationError.self) {
            try EpisodeSession(episode: episode, nodeID: "ending", flags: [:], completed: false)
        }
        #expect(throws: StoryEpisode.ValidationError.self) {
            try EpisodeSession(episode: episode, nodeID: "removed-node", flags: ["rest": false], completed: false)
        }
        #expect(throws: StoryEpisode.ValidationError.self) {
            try EpisodeSession(episode: episode, nodeID: episode.start, flags: ["unknown": true], completed: false)
        }
    }
}
