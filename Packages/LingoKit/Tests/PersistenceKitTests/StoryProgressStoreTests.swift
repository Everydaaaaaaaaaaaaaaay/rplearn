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
}
