import DomainKit
import Foundation
import PersistenceKit
import Testing
import UIKit
@testable import StoryEngine

@Suite("成人生活剧情版本与实际路径") @MainActor
struct AdultLifeEpisodeTests {
    @Test("二十条路径每页可恢复，所有结尾有独立经历，角色与画面都可载入")
    func allPathsRestore() throws {
        var endings = Set<String>()
        for currentID in DepartureStoryIdentity.currentEditions.values.sorted() {
            let url = try #require(Bundle.main.url(forResource: currentID, withExtension: "json"))
            let episode = try StoryEpisode.load(data: Data(contentsOf: url))
            #expect(episode.id == currentID)
            #expect(episode.version == 2)
            var visited = Set<String>()
            var paths = 0
            func visit(_ session: EpisodeSession) throws {
                visited.insert(session.nodeID)
                let saved = try JSONEncoder().encode(session.checkpoint)
                let restored = EpisodeSession(episode: episode, saved: saved)
                #expect(restored.checkpoint == session.checkpoint)
                #expect(restored.shot == session.shot)
                let synced = try EpisodeSession(episode: episode, nodeID: session.nodeID,
                                               flags: session.flags, completed: false)
                #expect(synced.history == session.history)
                if session.isFinished {
                    paths += 1
                    let outcome = try #require(session.current.experienceID)
                    let inserted = endings.insert(outcome).inserted
                    #expect(inserted)
                    #expect(session.decisionRecords.count == 2)
                    #expect(session.decisionRecords.allSatisfy { $0.outcome != nil })
                    let finished = try EpisodeSession(episode: episode, nodeID: nil,
                                                     flags: session.flags, completed: true)
                    #expect(finished.checkpoint == session.checkpoint)
                } else if let choices = session.current.choices {
                    for choice in choices {
                        var next = session
                        next.choose(choice.id)
                        try visit(next)
                    }
                } else {
                    var next = session
                    let advanced = next.advance()
                    #expect(advanced)
                    try visit(next)
                }
            }
            try visit(EpisodeSession(episode: episode))
            #expect(paths == 4)
            #expect(visited == Set(episode.nodes.map(\.id)))
            for name in episode.assetNames {
                #expect(Bundle.main.url(forResource: name, withExtension: "jpg") != nil
                    || Bundle.main.url(forResource: name, withExtension: "png") != nil || UIImage(named: name) != nil)
            }
        }
        #expect(endings.count == 20)
    }

    @Test("感谢不变邀约，离开不听到未选的申请开头")
    func branchCausality() throws {
        for (resource, first, second, expected) in [
            ("departures_mainline_singapore_v2", "b", "b", "SG22"),
            ("departures_mainline_melbourne_v2", "b", "b", "RB22"),
            ("departures_city_newyork_v2", "b", "b", "ML22"),
        ] {
            let url = try #require(Bundle.main.url(forResource: resource, withExtension: "json"))
            let episode = try StoryEpisode.load(data: Data(contentsOf: url))
            var session = EpisodeSession(episode: episode)
            var choices = [first, second]
            for _ in 0..<episode.nodes.count {
                if session.isFinished { break }
                if session.current.choices != nil { session.choose(choices.removeFirst()) }
                else { _ = session.advance() }
            }
            #expect(session.current.experienceID == expected)
            let text = session.history.compactMap { episode.node($0)?.text }.joined(separator: " ")
            #expect(!text.contains("bottle caps"))
            #expect(!text.contains("One friend can make time"))
        }
    }

    @Test("新版独立存档，旧进度与奖励身份保留，切换后优先续读新版")
    func editionIdentity() {
        for (original, current) in DepartureStoryIdentity.currentEditions {
            #expect(DepartureStoryIdentity.readingID(for: original, hasUnfinishedOriginal: false) == current)
            #expect(DepartureStoryIdentity.readingID(for: original, hasUnfinishedOriginal: true) == original)
            #expect(DepartureStoryIdentity.readingID(for: original, hasUnfinishedOriginal: true,
                                                    hasCurrentProgress: true) == current)
            #expect(DepartureStoryIdentity.catalogID(for: current) == original)
            #expect(DepartureStoryIdentity.catalogCompletionIDs([current]) == [original, current])
            #expect(DepartureStoryIdentity.rewardID(for: original) == DepartureStoryIdentity.rewardID(for: current))
        }
    }
}
