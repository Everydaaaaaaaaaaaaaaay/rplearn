import Foundation
import Testing
@testable import PersistenceKit

@Suite("EconomyStore")
struct EconomyStoreTests {
    private func makeStore() throws -> EconomyStore {
        EconomyStore(modelContainer: try ModelContainerFactory.makeContainer(inMemory: true))
    }

    @Test("默认档案：10 好友位、free 订阅、出题开")
    func defaultProfile() async throws {
        let store = try makeStore()
        let profile = try await store.profile()
        #expect(profile.friendSlotLimit == 10)
        #expect(profile.subscriptionTier == .free)
        #expect(profile.coins == 0)
        #expect(!profile.hasCompletedOnboarding)
    }

    @Test("金币增减与余额不足")
    func coins() async throws {
        let store = try makeStore()
        #expect(try await store.addCoins(100) == 100)
        #expect(try await store.spendCoins(30) == 70)
        await #expect(throws: EconomyStore.EconomyError.insufficientCoins) {
            try await store.spendCoins(1000)
        }
        // 失败不动余额
        #expect(try await store.profile().coins == 70)
    }

    @Test("档案更新会完整保存学习者资料与地区")
    func profileUpdate() async throws {
        let store = try makeStore()
        let placementDate = Date(timeIntervalSince1970: 1_774_972_800)
        _ = try await store.updateProfile { profile in
            profile.displayName = "旅人"
            profile.currentRegionID = "london"
            profile.starterRegionID = "london"
            profile.hasCompletedOnboarding = true
            profile.difficultyLevel = .senior2
            profile.learningGoal = .studyAbroad
            profile.studyStage = .seniorHigh
            profile.proficiencySource = .placement
            profile.placementScore = 72
            profile.placementCompletedAt = placementDate
            profile.hasCompletedProfileSetup = true
        }
        try await store.unlockRegion("london")
        try await store.unlockRegion("london") // 幂等
        let profile = try await store.profile()
        #expect(profile.displayName == "旅人")
        #expect(profile.currentRegionID == "london")
        #expect(profile.starterRegionID == "london")
        #expect(profile.unlockedRegionIDs == ["london"])
        #expect(profile.hasCompletedOnboarding)
        #expect(profile.difficultyLevel == .senior2)
        #expect(profile.learningGoal == .studyAbroad)
        #expect(profile.studyStage == .seniorHigh)
        #expect(profile.proficiencySource == .placement)
        #expect(profile.placementScore == 72)
        #expect(profile.placementCompletedAt == placementDate)
        #expect(profile.hasCompletedProfileSetup)
    }

    @Test("账号数据库路径稳定且账号之间互不相同")
    func accountStorePathsArePartitioned() {
        let root = URL.temporaryDirectory.appending(
            path: "AccountStorePaths-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let first = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456701")!
        let second = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456702")!

        let firstURL = AccountStoreLocation.storeURL(
            for: first,
            applicationSupportDirectory: root
        )
        let secondURL = AccountStoreLocation.storeURL(
            for: second,
            applicationSupportDirectory: root
        )

        #expect(firstURL != secondURL)
        #expect(firstURL.lastPathComponent == "LingoTrip.store")
        #expect(firstURL.deletingLastPathComponent().lastPathComponent == first.uuidString.lowercased())
        #expect(secondURL.deletingLastPathComponent().lastPathComponent == second.uuidString.lowercased())
    }

    @Test("旧数据库只导入其账号且保留可恢复的源文件")
    func legacyStoreImportChecksOwnershipAndPreservesSource() throws {
        let fileManager = FileManager.default
        let root = URL.temporaryDirectory.appending(
            path: "LegacyStoreImport-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appending(path: "default.store")
        let wal = URL(filePath: legacy.path + "-wal")
        let shm = URL(filePath: legacy.path + "-shm")
        try Data("database".utf8).write(to: legacy)
        try Data("wal".utf8).write(to: wal)
        try Data("shm".utf8).write(to: shm)

        let owner = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456703")!
        let other = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456704")!
        let rejected = try AccountStoreLocation.prepare(
            for: other,
            legacyOwnerID: owner,
            legacyWasGuest: false,
            applicationSupportDirectory: root,
            fileManager: fileManager
        )
        #expect(!rejected.importedLegacyStore)
        #expect(!fileManager.fileExists(atPath: rejected.storeURL.path))

        let imported = try AccountStoreLocation.prepare(
            for: owner,
            legacyOwnerID: owner,
            legacyWasGuest: false,
            applicationSupportDirectory: root,
            fileManager: fileManager
        )
        #expect(imported.importedLegacyStore)
        #expect(try Data(contentsOf: imported.storeURL) == Data("database".utf8))
        #expect(try Data(contentsOf: URL(filePath: imported.storeURL.path + "-wal")) == Data("wal".utf8))
        #expect(try Data(contentsOf: URL(filePath: imported.storeURL.path + "-shm")) == Data("shm".utf8))
        #expect(try Data(contentsOf: legacy) == Data("database".utf8))
        #expect(try Data(contentsOf: wal) == Data("wal".utf8))
        #expect(try Data(contentsOf: shm) == Data("shm".utf8))
    }

    @Test("两个磁盘账号容器的数据完全不可互见")
    func diskBackedAccountContainersAreIsolated() async throws {
        let fileManager = FileManager.default
        let root = URL.temporaryDirectory.appending(
            path: "AccountContainerIsolation-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let firstID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456705")!
        let secondID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456706")!
        let firstPreparation = try AccountStoreLocation.prepare(
            for: firstID,
            legacyOwnerID: nil,
            legacyWasGuest: false,
            applicationSupportDirectory: root,
            fileManager: fileManager
        )
        let secondPreparation = try AccountStoreLocation.prepare(
            for: secondID,
            legacyOwnerID: nil,
            legacyWasGuest: false,
            applicationSupportDirectory: root,
            fileManager: fileManager
        )
        let firstStore = EconomyStore(
            modelContainer: try ModelContainerFactory.makeContainer(
                storeURL: firstPreparation.storeURL
            )
        )
        let secondStore = EconomyStore(
            modelContainer: try ModelContainerFactory.makeContainer(
                storeURL: secondPreparation.storeURL
            )
        )

        _ = try await firstStore.addCoins(111)
        _ = try await secondStore.addCoins(7)

        #expect(try await firstStore.profile().coins == 111)
        #expect(try await secondStore.profile().coins == 7)
        #expect(firstPreparation.storeURL != secondPreparation.storeURL)
    }
}
