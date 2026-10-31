import Foundation
import Testing
@testable import PersistenceKit

@Suite("StoryProgressStore")
struct StoryProgressStoreTests {
    private func makeStore() throws -> StoryProgressStore {
        StoryProgressStore(modelContainer: try ModelContainerFactory.makeContainer(inMemory: true))
    }

    @Test("断点保存与恢复")
    func checkpointRoundTrip() async throws {
        let store = try makeStore()
        #expect(try await store.progress(storyID: "s1") == nil)

        try await store.saveCheckpoint(storyID: "s1", nodeID: "n05", flags: ["brave": true])
        let progress = try await store.progress(storyID: "s1")
        #expect(progress?.currentNodeID == "n05")
        #expect(progress?.flags == ["brave": true])
        #expect(progress?.isCompleted == false)
    }

    @Test("标记完成后清空断点")
    func completion() async throws {
        let store = try makeStore()
        try await store.saveCheckpoint(storyID: "s1", nodeID: "n10", flags: [:])
        try await store.markCompleted(storyID: "s1")
        let progress = try await store.progress(storyID: "s1")
        #expect(progress?.isCompleted == true)
        #expect(progress?.currentNodeID == nil)
        #expect(try await store.completedStoryIDs() == ["s1"])
    }

    @Test("重玩只替换阅读断点，保留完成账本和首次完成时间")
    func replayKeepsCompletion() async throws {
        let store = try makeStore()
        try await store.markCompleted(storyID: "departures_city_london_v1")
        let first = try await store.progress(storyID: "departures_city_london_v1")
        try await store.saveCheckpoint(storyID: "departures_city_london_v1", nodeID: "arrival", flags: [:])
        let replay = try await store.progress(storyID: "departures_city_london_v1")
        #expect(replay?.completedAt == first?.completedAt)
        #expect(replay?.currentNodeID == "arrival")
    }
    @Test("完成结果只记第一次，重玩不能抹掉或伪造；新版与目录标志一并保存")
    func preservesFirstExperienceAndCatalog() async throws {
        let store = try makeStore()
        try await store.saveCheckpoint(storyID: "new", nodeID: "endA", flags: ["choice": true, "experience.fake": true])
        #expect(try await store.progress(storyID: "new")?.flags["experience.fake"] == nil)
        try await store.markCompleted(storyID: "new", experienceID: "A", catalogStoryID: "catalog")
        let first = try #require(await store.progress(storyID: "new"))
        #expect(try await store.completedStoryIDs() == ["new", "catalog"])
        try await store.saveCheckpoint(storyID: "new", nodeID: "endB", flags: ["choice": false])
        try await store.markCompleted(storyID: "new", experienceID: "B", catalogStoryID: "catalog")
        let replay = try #require(await store.progress(storyID: "new"))
        #expect(replay.completedAt == first.completedAt)
        #expect(replay.flags["experience.A"] == true)
        #expect(replay.flags["experience.B"] == nil)
        #expect(replay.readingFlags == ["choice": false])
    }

    @Test("新版完成不覆盖旧版未读完的节点、分支和完成状态")
    func preservesOriginalCheckpoint() async throws {
        let store = try makeStore()
        try await store.saveCheckpoint(storyID: "old", nodeID: "old-node", flags: ["old-choice": true])
        let before = try await store.progress(storyID: "old")
        try await store.markCompleted(storyID: "new", experienceID: "B", catalogStoryID: "old")
        #expect(try await store.progress(storyID: "old") == before)
    }

}
