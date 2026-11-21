import DomainKit
import Foundation
import Testing
import UIKit
@testable import StoryEngine

@Suite("剧情编辑新版与历史续读") @MainActor
struct EditorialEpisodeTests {
    @Test("二十篇新版的五十六条路径逐页恢复，画面与目录一致")
    func publishedPaths() throws {
        let catalogURL = try #require(Bundle.main.url(forResource: "departures_catalog", withExtension: "json"))
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        #expect(catalog["currentEditions"] as? [String: String] == DepartureStoryIdentity.currentEditions)
        #expect(catalog["previousEditions"] as? [String: [String]] == DepartureStoryIdentity.previousEditions)
        #expect(DepartureStoryIdentity.currentEditions.count == 20)
        var allOutcomes = Set<String>()
        var pathCount = 0
        for resource in DepartureStoryIdentity.currentEditions.values.sorted() {
            let url = try #require(Bundle.main.url(forResource: resource, withExtension: "json"))
            let episode = try StoryEpisode.load(data: Data(contentsOf: url))
            #expect(episode.id == resource)
            #expect(resource.hasSuffix("_v\(episode.version)"))
            var reached = Set<String>()
            func walk(_ session: EpisodeSession) throws {
                reached.insert(session.nodeID)
                let data = try JSONEncoder().encode(session.checkpoint)
                let restored = EpisodeSession(episode: episode, saved: data)
                #expect(restored.checkpoint == session.checkpoint)
                #expect(restored.shot == session.shot)
                let synced = try EpisodeSession(episode: episode, nodeID: session.nodeID,
                                               flags: session.flags, completed: false)
                #expect(synced.history == session.history)
                if session.isFinished {
                    pathCount += 1
                    let outcome = try #require(session.current.experienceID)
                    let inserted = allOutcomes.insert(outcome).inserted
                    #expect(inserted)
                    #expect(session.decisionRecords.allSatisfy { $0.outcome != nil })
                    let completed = try EpisodeSession(episode: episode, nodeID: nil,
                                                      flags: session.flags, completed: true)
                    #expect(completed.checkpoint == session.checkpoint)
                } else if let choices = session.current.choices {
                    for choice in choices {
                        var next = session
                        next.choose(choice.id)
                        try walk(next)
                    }
                } else {
                    var next = session
                    let advanced = next.advance()
                    #expect(advanced)
                    try walk(next)
                }
            }
            try walk(EpisodeSession(episode: episode))
            #expect(reached == Set(episode.nodes.map(\.id)))
            for asset in episode.assetNames {
                #expect(Bundle.main.url(forResource: asset, withExtension: "jpg") != nil
                    || Bundle.main.url(forResource: asset, withExtension: "png") != nil
                    || UIImage(named: asset) != nil)
            }
        }
        #expect(pathCount == 56)
        #expect(allOutcomes.count == pathCount)
    }

    @Test("新版开场、对话和分支使用与现场相符的角色镜头")
    func authoredCharacterShots() throws {
        func load(_ chapterID: String) throws -> StoryEpisode {
            let resource = try #require(DepartureStoryIdentity.currentEditions[chapterID])
            let url = try #require(Bundle.main.url(forResource: resource, withExtension: "json"))
            return try StoryEpisode.load(data: Data(contentsOf: url))
        }
        func shot(_ episode: StoryEpisode, _ nodeID: String) throws -> StoryEpisode.Shot {
            let node = try #require(episode.node(nodeID))
            return try #require(episode.shots[node.shot])
        }

        let london = try load("departures_london_v1")
        #expect(try shot(london, "start").actors.isEmpty)
        #expect(try shot(london, "start_2").actors.map(\.asset) == ["dp_oliver_welcome"])
        #expect(try shot(london, "inside_7").actors.map(\.asset) == ["dp_oliver_manuscript"])
        #expect(try shot(london, "list_4").actors.map(\.id) == ["Nora", "Oliver"])
        #expect(try shot(london, "read_window").background == "dp_oliver_listening")

        let singapore = try load("departures_mainline_singapore_v1")
        #expect(try shot(singapore, "start_2").background == "dp_mei_dinner")
        #expect(try shot(singapore, "eat_end_2").background == "dp_singapore_outside")

        let auckland = try load("departures_city_auckland_v1")
        #expect(try shot(auckland, "drawer_3").actors.map(\.id) == ["Peter"])
    }

    @Test("中间版 v2 续读、已读、奖励和新版切换均保留")
    func intermediateEditions() throws {
        for (original, olderEditions) in DepartureStoryIdentity.previousEditions {
            let current = try #require(DepartureStoryIdentity.currentEditions[original])
            for older in olderEditions {
                #expect(DepartureStoryIdentity.catalogID(for: older) == original)
                #expect(DepartureStoryIdentity.rewardID(for: older) == DepartureStoryIdentity.rewardID(for: current))
                #expect(DepartureStoryIdentity.catalogCompletionIDs([older]).contains(original))
                #expect(DepartureStoryIdentity.readingID(for: original, unfinishedEditions: [original, older],
                    startedEditions: [original, older]) == older)
                #expect(DepartureStoryIdentity.readingID(for: original, unfinishedEditions: [older],
                    startedEditions: [older, current]) == current)
                #expect(DepartureStoryIdentity.readingID(for: original, unfinishedEditions: [],
                    startedEditions: [older]) == current)
                #expect(DepartureStoryIdentity.readingEditions(for: older).contains(current))
            }
        }
    }
}
