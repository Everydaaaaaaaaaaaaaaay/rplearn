import Foundation
import Testing
@testable import StoryEngine

@Suite("伦敦演出样章")
struct StoryEpisodeTests {
    private func bundledData() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: "departures_london_v1", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test("70 个节点、8 份美术、6 幕完整演出且资源均随包")
    func resources() throws {
        let episode = try StoryEpisode.load(data: bundledData())
        #expect(episode.nodes.count == 70)
        #expect(episode.assetNames.count == 8)
        #expect(episode.acts.count == 6)
        for name in episode.assetNames {
            let suffix = name.hasPrefix("oliver") || name.hasPrefix("nora") ? "png" : "jpg"
            #expect(Bundle.main.url(forResource: name, withExtension: suffix) != nil)
        }
    }

    @Test("活动开始后人物仍在活动角，不因换说话人跳回书架对话区")
    func readingSceneContinuity() throws {
        let episode = try StoryEpisode.load(data: bundledData())
        for node in episode.nodes where node.act == 3 && !["read_yes", "listen_yes"].contains(node.id) {
            let shot = try #require(episode.shots[node.shot])
            #expect(["london_reading", "london_reading_cg"].contains(shot.background))
        }
    }

    @Test("四条路线完整收束，每一步存档恢复相同场景、决策和历史", arguments: [true, false], [true, false])
    func routesAndResume(privateFirst: Bool, reads: Bool) throws {
        let episode = try StoryEpisode.load(data: bundledData())
        var session = EpisodeSession(episode: episode)
        var iterations = 0
        while !session.isFinished && iterations < episode.nodes.count {
            let snapshot = try JSONEncoder().encode(session.checkpoint)
            let resumed = EpisodeSession(episode: episode, saved: snapshot)
            #expect(resumed.checkpoint == session.checkpoint)
            #expect(resumed.flags == session.flags)
            #expect(resumed.shot == session.shot)
            #expect(resumed.history == session.history)
            if session.nodeID == "approach" { session.choose(privateFirst ? "private" : "format") }
            else if session.nodeID == "tonight" { session.choose(reads ? "read" : "listen") }
            else { let advanced = session.advance(); #expect(advanced) }
            iterations += 1
        }
        #expect(session.isFinished)
        #expect(session.flags["askedPrivately"] == privateFirst)
        #expect(session.flags["readTonight"] == reads)
        #expect(session.history.contains(reads ? "read_finish" : "listen_commit"))
        #expect(session.history.contains(privateFirst ? "remember_private" : "remember_format"))
        let complete = EpisodeSession(episode: episode, saved: try JSONEncoder().encode(session.checkpoint))
        #expect(complete.isFinished)
        let advancedPastEnding = session.advance()
        #expect(!advancedPastEnding)
    }

    @Test("选择节点不能被普通继续跳过，无效选择不改变状态")
    func choiceGuard() throws {
        var session = EpisodeSession(episode: try StoryEpisode.load(data: bundledData()))
        while session.current.choices == nil { let advanced = session.advance(); #expect(advanced) }
        let snapshot = session.checkpoint
        let advancedPastChoice = session.advance()
        #expect(!advancedPastChoice)
        session.choose("missing")
        #expect(session.checkpoint == snapshot)
    }

    @Test("损坏、旧版本和伪造决策存档安全重启")
    func invalidCheckpoints() throws {
        let episode = try StoryEpisode.load(data: bundledData())
        let cases = [
            Data("not json".utf8),
            Data(#"{"episodeID":"departures_london","version":99,"nodeID":"ending","decisions":{}}"#.utf8),
            Data(#"{"episodeID":"departures_london","version":1,"nodeID":"ending","decisions":{}}"#.utf8),
            Data(#"{"episodeID":"departures_london","version":1,"nodeID":"arrival","decisions":{"approach":"private"}}"#.utf8),
        ]
        for data in cases { #expect(EpisodeSession(episode: episode, saved: data).nodeID == episode.start) }
    }

    @Test("拒绝悬空、重复、循环、空选择及缺失镜头")
    func invalidScripts() throws {
        let original = try #require(JSONSerialization.jsonObject(with: bundledData()) as? [String: Any])
        for mutation in 0..<5 {
            var file = original
            var nodes = try #require(file["nodes"] as? [[String: Any]])
            switch mutation {
            case 0: nodes[0]["next"] = "missing"
            case 1: nodes[1]["id"] = nodes[0]["id"]
            case 2: nodes[0]["next"] = "arrival"
            case 3:
                nodes[0].removeValue(forKey: "next")
                nodes[0]["choices"] = []
            default: nodes[0]["shot"] = "missing"
            }
            file["nodes"] = nodes
            let data = try JSONSerialization.data(withJSONObject: file)
            #expect(throws: StoryEpisode.ValidationError.self) { try StoryEpisode.load(data: data) }
        }
    }
}
