import BackendKit
import DomainKit
import Foundation
import PersistenceKit

public enum UserStateActivation: Sendable, Equatable {
    case offlineCache
    case cached
    case synchronized
}

/// 把跨平台服务器状态投影到 SwiftData。所有资产修改仍由服务端事务决定。
public actor BackendUserStateCoordinator:
    ProfileCommandGateway,
    OnboardingCommandGateway,
    ProgressionRewardGateway,
    TicketPurchaseGateway,
    TravelCommandGateway
{
    private struct PendingCommand: Codable, Sendable {
        let createdAt: Date
        let id: UUID
    }

    private struct ProfilePatch: Encodable, Sendable {
        let difficulty: String?
        let displayName: String?
        let expectedVersion: Int
        let hasCompletedOnboarding: Bool?
        let hasCompletedProfileSetup: Bool?
        let learningGoal: String?
        let placementCompletedAt: String?
        let placementScore: Int?
        let proficiencySource: String?
        let studyStage: String?
    }

    private struct TicketPurchase: Encodable, Sendable {
        let countryCode: String?
        let type: String
    }

    private struct TravelCommand: Encodable, Sendable {
        let targetRegionId: String
        let ticketId: UUID?
    }

    private struct OnboardingCommand: Encodable, Sendable {
        let starterRegionId: String
    }

    private struct EmptyCommand: Encodable, Sendable {}

    private let backend: BackendClient
    private var requestBackend: BackendClient
    private let guestOwnerKey = "backend.state.guest-owner.v1"
    private let accountCache: AccountCacheStore
    private let economyCache: EconomyStore
    private let itemCache: ItemStore
    private let ticketStubCache: TicketStubStore
    private let defaults: UserDefaults
    private let accountStorageUserID: UUID?
    private let cachedOwnerKey = "backend.state.cached-owner.v1"
    private let cursorKeyPrefix = "backend.sync.cursor.v1."
    private let pendingCommandsKey = "backend.commands.pending.v1"
    private var currentUserID: UUID?
    private var snapshot: BackendSyncSnapshot?
    private var isImportingGuest = false

    public init(
        backend: BackendClient,
        accountCache: AccountCacheStore,
        economyCache: EconomyStore,
        itemCache: ItemStore,
        ticketStubCache: TicketStubStore,
        accountStorageUserID: UUID? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.backend = backend
        self.requestBackend = backend
        self.accountCache = accountCache
        self.economyCache = economyCache
        self.itemCache = itemCache
        self.ticketStubCache = ticketStubCache
        self.accountStorageUserID = accountStorageUserID
        self.defaults = defaults
    }

    public func activate(userID: UUID, preferCache: Bool = false) async throws -> UserStateActivation {
        if let accountStorageUserID, accountStorageUserID != userID {
            throw BackendClientError.invalidResponse
        }
        let owner = defaults.string(forKey: cachedOwnerKey).flatMap(UUID.init(uuidString:))
        let hasCursor = cursor(for: userID) != nil
        let hasCachedProfile = try await accountCache.hasCachedProfile()
        let hasAccountSnapshot = hasCursor && hasCachedProfile
        let cacheBelongsToUser = accountStorageUserID == userID || owner == userID
        let canUseOfflineCache = hasAccountSnapshot && cacheBelongsToUser
        let isAccountSwitch = accountStorageUserID == nil
            && owner != nil
            && owner != userID
            && !defaults.bool(forKey: guestOwnerKey)
        if isAccountSwitch {
            try await accountCache.clearAll()
            snapshot = nil
        }
        requestBackend = backend
        currentUserID = userID
        prunePendingCommands()

        // 仅复用已核验归属且完整的快照；首次登录仍需获取服务器状态。
        if preferCache, canUseOfflineCache {
            return .cached
        }

        do {
            if canUseOfflineCache, cursor(for: userID) != nil {
                try await synchronizeChanges(for: userID)
            } else {
                try await refreshSnapshot(for: userID)
            }
            defaults.set(userID.uuidString.lowercased(), forKey: cachedOwnerKey)
            defaults.set(false, forKey: guestOwnerKey)
            return .synchronized
        } catch let error as BackendClientError {
            if case .transport = error, canUseOfflineCache {
                return .offlineCache
            }
            throw error
        }
    }

    /// 只有从未绑定过账号的游客空间才可以把本地学习者资料导入首次登录账号。
    public func shouldCaptureGuestProfileForImport() -> Bool {
        defaults.bool(forKey: guestOwnerKey) || defaults.string(forKey: cachedOwnerKey) == nil
    }

    /// 账号已完成建档时以云端为准；否则一次性导入游客在登录前填写的资料。
    public func importGuestLearnerProfileIfNeeded(
        _ guestProfile: UserProfileDTO
    ) async throws -> UserProfileDTO {
        guard guestProfile.hasCompletedProfileSetup,
              snapshot?.state.profile.hasCompletedProfileSetup != true
        else {
            guard let current = snapshot?.state.profile else {
                throw BackendClientError.invalidResponse
            }
            return await mapPreservingEntitlement(current)
        }
        return try await updateProfile { profile in
            profile.displayName = guestProfile.displayName
            profile.difficultyLevel = guestProfile.difficultyLevel
            profile.learningGoal = guestProfile.learningGoal
            profile.studyStage = guestProfile.studyStage
            profile.proficiencySource = guestProfile.proficiencySource
            profile.placementScore = guestProfile.placementScore
            profile.placementCompletedAt = guestProfile.placementCompletedAt
            profile.hasCompletedProfileSetup = true
        }
    }

    /// 切换到游客空间。只有设备上曾激活过账号时才清理缓存，避免误删既有游客进度。
    public func activateGuest() async throws {
        currentUserID = nil
        snapshot = nil
        if defaults.string(forKey: cachedOwnerKey) != nil && !defaults.bool(forKey: guestOwnerKey) {
            try await accountCache.clearAll()
            defaults.removeObject(forKey: cachedOwnerKey)
        }
        // Also revoke cached development-only Pro access for existing guests.
        // Only entitlements change; existing guest friends, assets and progress remain intact.
        try await economyCache.applyAuthoritativeEntitlement(tier: .free, friendSlotLimit: 3)
    }

    /// Upgrade an existing offline guest without accepting client-supplied coins or tickets.
    /// Local content remains in place; recognized achievements are replayed idempotently.
    public func activateAnonymous(
        legacyProfile: UserProfileDTO,
        completedStories: Set<String>,
        hadStarterTicket: Bool
    ) async throws {
        let client = try await backend.anonymousClient()
        guard let identity = try await client.cachedIdentity() else { throw BackendClientError.signedOut }
        requestBackend = client
        currentUserID = identity.userID
        isImportingGuest = true
        defer { isImportingGuest = false }
        // Load before applying, so a network error cannot erase offline onboarding details.
        let loaded: BackendSyncSnapshot = try await client.get("/v1/sync/snapshot")
        snapshot = loaded
        if legacyProfile.hasCompletedOnboarding, !loaded.state.profile.hasCompletedOnboarding {
            _ = try await completeOnboarding(starterRegionID: legacyProfile.starterRegionID ?? "london")
        }
        if legacyProfile.hasCompletedProfileSetup {
            _ = try await importGuestLearnerProfileIfNeeded(legacyProfile)
        }
        let starter = snapshot?.state.profile.starterRegionId ?? legacyProfile.starterRegionID ?? "london"
        for story in completedStories where JourneyAccess(isGuest: true).allowsStory(story, starterRegionID: starter) {
            _ = try await completeStory(story)
        }
        if hadStarterTicket, snapshot?.state.profile.hasCompletedOnboarding == true {
            _ = try await claimStarterTicket()
        }
        try await refreshSnapshot(for: identity.userID)
        isImportingGuest = false
        if let snapshot { try await apply(snapshot) }
        defaults.set(identity.userID.uuidString.lowercased(), forKey: cachedOwnerKey)
        defaults.set(true, forKey: guestOwnerKey)
        try await economyCache.applyAuthoritativeEntitlement(tier: .free, friendSlotLimit: 3)
    }

    public func synchronize() async throws {
        guard let currentUserID else {
            throw BackendClientError.signedOut
        }
        try await synchronizeChanges(for: currentUserID)
    }

    public func updateProfile(
        _ mutate: @Sendable (inout UserProfileDTO) -> Void
    ) async throws -> UserProfileDTO {
        try await updateProfile(mutate, retryAfterConflict: true)
    }

    private func updateProfile(
        _ mutate: @Sendable (inout UserProfileDTO) -> Void,
        retryAfterConflict: Bool
    ) async throws -> UserProfileDTO {
        if snapshot == nil { try await refreshCurrentSnapshot() }
        guard let current = snapshot?.state.profile else {
            throw BackendClientError.invalidResponse
        }
        var desired = await mapPreservingEntitlement(current)
        mutate(&desired)
        let patch = ProfilePatch(
            difficulty: desired.difficultyLevel.rawValue == current.difficulty
                ? nil : desired.difficultyLevel.rawValue,
            displayName: desired.displayName == current.displayName ? nil : desired.displayName,
            expectedVersion: current.version,
            hasCompletedOnboarding: desired.hasCompletedOnboarding
                == current.hasCompletedOnboarding ? nil : desired.hasCompletedOnboarding,
            hasCompletedProfileSetup: desired.hasCompletedProfileSetup
                == (current.hasCompletedProfileSetup ?? false) ? nil : desired.hasCompletedProfileSetup,
            learningGoal: desired.learningGoal.rawValue
                == (current.learningGoal ?? LearningGoal.dailyConversation.rawValue)
                ? nil : desired.learningGoal.rawValue,
            placementCompletedAt: desired.placementCompletedAt.flatMap { date in
                current.placementCompletedAt == Self.isoString(date) ? nil : Self.isoString(date)
            },
            placementScore: desired.placementScore == current.placementScore
                ? nil : desired.placementScore,
            proficiencySource: desired.proficiencySource.rawValue
                == (current.proficiencySource ?? ProficiencySource.selfReported.rawValue)
                ? nil : desired.proficiencySource.rawValue,
            studyStage: desired.studyStage?.rawValue == current.studyStage
                ? nil : desired.studyStage?.rawValue
        )
        guard patch.difficulty != nil
            || patch.displayName != nil
            || patch.hasCompletedOnboarding != nil
            || patch.hasCompletedProfileSetup != nil
            || patch.learningGoal != nil
            || patch.placementCompletedAt != nil
            || patch.placementScore != nil
            || patch.proficiencySource != nil
            || patch.studyStage != nil
        else {
            return desired
        }
        let onboardingValue = patch.hasCompletedOnboarding.map { String($0) } ?? "-"
        let intentParts: [String] = [
            "profile",
            String(current.version),
            patch.difficulty ?? "-",
            patch.displayName ?? "-",
            onboardingValue,
            patch.hasCompletedProfileSetup.map { String($0) } ?? "-",
            patch.learningGoal ?? "-",
            patch.placementCompletedAt ?? "-",
            patch.placementScore.map { String($0) } ?? "-",
            patch.proficiencySource ?? "-",
            patch.studyStage ?? "-",
        ]
        let intent = intentParts.joined(separator: ":")
        let commandID = pendingCommandID(for: intent)
        do {
            let _: BackendUserProfile = try await requestBackend.send(
                path: "/v1/me",
                method: "PATCH",
                body: patch,
                idempotencyKey: commandID
            )
            try await refreshCurrentSnapshot()
            completeCommand(for: intent)
            guard let updated = snapshot?.state.profile else {
                throw BackendClientError.invalidResponse
            }
            return await mapPreservingEntitlement(updated)
        } catch let error as BackendClientError {
            if error.code == "PROFILE_VERSION_CONFLICT", retryAfterConflict {
                completeCommand(for: intent)
                try await refreshCurrentSnapshot()
                return try await updateProfile(mutate, retryAfterConflict: false)
            }
            abandonCommand(for: intent, ifDeterministic: error)
            throw error
        }
    }

    public func purchaseTicket(
        type: ItemType,
        countryCode: String?
    ) async throws -> ItemDTO {
        let normalizedCountry = type == .ticketCountry ? countryCode?.uppercased() : nil
        let intent = "ticket:\(type.rawValue):\(normalizedCountry ?? "-")"
        let commandID = pendingCommandID(for: intent)
        do {
            let result: BackendTicketPurchaseResult = try await requestBackend.send(
                path: "/v1/economy/tickets/purchase",
                method: "POST",
                body: TicketPurchase(
                    countryCode: normalizedCountry,
                    type: type == .ticketUniversal ? "universal" : "country"
                ),
                idempotencyKey: commandID
            )
            try await refreshCurrentSnapshot()
            completeCommand(for: intent)
            return try map(result.ticket)
        } catch let error as BackendClientError {
            abandonCommand(for: intent, ifDeterministic: error)
            throw error
        }
    }

    public func claimStarterTicket() async throws -> Bool {
        let intent = "progression:starter-ticket-v1"
        let commandID = pendingCommandID(for: intent)
        do {
            let _: BackendTicket = try await requestBackend.send(
                path: "/v1/progression/starter-ticket",
                method: "POST",
                body: EmptyCommand(),
                idempotencyKey: commandID
            )
            try await refreshCurrentSnapshot()
            completeCommand(for: intent)
            return true
        } catch let error as BackendClientError {
            if error.code == "STARTER_TICKET_ALREADY_CLAIMED" {
                completeCommand(for: intent)
                try await refreshCurrentSnapshot()
                return false
            }
            abandonCommand(for: intent, ifDeterministic: error)
            throw error
        }
    }

    public func completeOnboarding(starterRegionID: String) async throws -> UserProfileDTO {
        let intent = "progression:onboarding:\(starterRegionID)"
        let commandID = pendingCommandID(for: intent)
        do {
            let updated: BackendUserProfile = try await requestBackend.send(
                path: "/v1/progression/onboarding",
                method: "POST",
                body: OnboardingCommand(starterRegionId: starterRegionID),
                idempotencyKey: commandID
            )
            let profile = await mapPreservingEntitlement(updated)
            if !isImportingGuest { try await economyCache.replaceAuthoritativeProfile(profile) }
            if let current = snapshot {
                snapshot = BackendSyncSnapshot(
                    cursor: current.cursor,
                    state: BackendUserSnapshot(
                        firstArrivals: current.state.firstArrivals,
                        profile: updated,
                        tickets: current.state.tickets
                    )
                )
            }
            completeCommand(for: intent)
            return profile
        } catch let error as BackendClientError {
            abandonCommand(for: intent, ifDeterministic: error)
            throw error
        }
    }

    public func completeStory(_ storyID: String) async throws -> Bool {
        try await completeStoryReward(storyID) != nil
    }

    public func completeStoryReward(_ storyID: String) async throws -> Int? {
        let intent = "progression:story:\(storyID)"
        let commandID = pendingCommandID(for: intent)
        do {
            let result: BackendStoryCompletion = try await requestBackend.send(
                path: "/v1/progression/stories/\(storyID)/complete",
                method: "POST",
                body: EmptyCommand(),
                idempotencyKey: commandID
            )
            try await refreshCurrentSnapshot()
            completeCommand(for: intent)
            return result.rewardCoins
        } catch let error as BackendClientError {
            if error.code == "STORY_ALREADY_COMPLETED" {
                completeCommand(for: intent)
                try await refreshCurrentSnapshot()
                return nil
            }
            abandonCommand(for: intent, ifDeterministic: error)
            throw error
        }
    }

    public func travel(
        targetRegionID: String,
        ticketID: UUID?
    ) async throws -> TravelCommandResult {
        let intent = "travel:\(targetRegionID):\(ticketID?.uuidString.lowercased() ?? "-")"
        let commandID = pendingCommandID(for: intent)
        do {
            let result: BackendTravelResult = try await requestBackend.send(
                path: "/v1/travel",
                method: "POST",
                body: TravelCommand(targetRegionId: targetRegionID, ticketId: ticketID),
                idempotencyKey: commandID
            )
            try await refreshCurrentSnapshot()
            completeCommand(for: intent)
            return TravelCommandResult(
                fromRegionID: result.fromRegionId,
                toRegionID: result.toRegionId,
                travelID: result.travelId,
                traveledAt: try parseDate(result.traveledAt),
                unlockedNow: result.unlockedNow
            )
        } catch let error as BackendClientError {
            abandonCommand(for: intent, ifDeterministic: error)
            throw error
        }
    }

    private func synchronizeChanges(for userID: UUID) async throws {
        guard var nextCursor = cursor(for: userID) else {
            try await refreshSnapshot(for: userID)
            return
        }
        var foundChanges = false
        do {
            repeat {
                let page: BackendSyncPage = try await requestBackend.get(
                    "/v1/sync/changes",
                    queryItems: [
                        URLQueryItem(name: "cursor", value: nextCursor),
                        URLQueryItem(name: "limit", value: "100"),
                    ]
                )
                foundChanges = foundChanges || !page.changes.isEmpty
                nextCursor = page.nextCursor
                setCursor(nextCursor, for: userID)
                if !page.hasMore { break }
            } while true
        } catch let error as BackendClientError {
            if error.code == "INVALID_SYNC_CURSOR" {
                try await refreshSnapshot(for: userID)
                return
            }
            throw error
        }
        if foundChanges || snapshot == nil {
            try await refreshSnapshot(for: userID)
        }
    }

    private func refreshCurrentSnapshot() async throws {
        guard let currentUserID else {
            throw BackendClientError.signedOut
        }
        try await refreshSnapshot(for: currentUserID)
    }

    private func refreshSnapshot(for userID: UUID) async throws {
        let loaded: BackendSyncSnapshot = try await requestBackend.get("/v1/sync/snapshot")
        try await apply(loaded)
        snapshot = loaded
        setCursor(loaded.cursor, for: userID)
    }

    private func apply(_ loaded: BackendSyncSnapshot) async throws {
        guard !isImportingGuest else { return }
        let profile = await mapPreservingEntitlement(loaded.state.profile)
        let tickets = try loaded.state.tickets.map(map)
        try await economyCache.replaceAuthoritativeProfile(profile)
        try await itemCache.replaceAvailableTickets(tickets)
        for arrival in loaded.state.firstArrivals {
            _ = try await ticketStubCache.cacheFirstServerArrival(
                id: arrival.id,
                fromRegionID: arrival.fromRegionId,
                toRegionID: arrival.toRegionId,
                usedAt: try parseDate(arrival.arrivedAt)
            )
        }
    }

    private func cursor(for userID: UUID) -> String? {
        defaults.string(forKey: cursorKeyPrefix + userID.uuidString.lowercased())
    }

    private func setCursor(_ cursor: String, for userID: UUID) {
        defaults.set(cursor, forKey: cursorKeyPrefix + userID.uuidString.lowercased())
    }

    private func commandKey(for intent: String) -> String {
        "\(currentUserID?.uuidString.lowercased() ?? "signed-out")|\(intent)"
    }

    private func pendingCommandID(for intent: String) -> UUID {
        var commands = pendingCommands()
        let key = commandKey(for: intent)
        if let existing = commands[key] {
            return existing.id
        }
        let created = PendingCommand(createdAt: .now, id: UUID())
        commands[key] = created
        savePendingCommands(commands)
        return created.id
    }

    private func completeCommand(for intent: String) {
        var commands = pendingCommands()
        commands.removeValue(forKey: commandKey(for: intent))
        savePendingCommands(commands)
    }

    private func abandonCommand(
        for intent: String,
        ifDeterministic error: BackendClientError
    ) {
        if case .api(_, _, _, let status) = error, (400..<500).contains(status) {
            completeCommand(for: intent)
        }
    }

    private func pendingCommands() -> [String: PendingCommand] {
        guard let data = defaults.data(forKey: pendingCommandsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: PendingCommand].self, from: data)) ?? [:]
    }

    private func savePendingCommands(_ commands: [String: PendingCommand]) {
        if commands.isEmpty {
            defaults.removeObject(forKey: pendingCommandsKey)
        } else if let data = try? JSONEncoder().encode(commands) {
            defaults.set(data, forKey: pendingCommandsKey)
        }
    }

    private func prunePendingCommands() {
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        savePendingCommands(
            pendingCommands().filter { $0.value.createdAt >= cutoff }
        )
    }

    private func map(_ profile: BackendUserProfile) -> UserProfileDTO {
        UserProfileDTO(
            displayName: profile.displayName,
            currentRegionID: profile.currentRegionId,
            starterRegionID: profile.starterRegionId,
            coins: profile.coins,
            subscriptionTier: .free,
            friendSlotLimit: profile.friendSlotLimit,
            unlockedRegionIDs: profile.unlockedRegionIds,
            difficultyLevel: DifficultyLevel(rawValue: profile.difficulty) ?? .junior1,
            hasCompletedOnboarding: profile.hasCompletedOnboarding,
            learningGoal: profile.learningGoal.flatMap(LearningGoal.init(rawValue:))
                ?? .dailyConversation,
            studyStage: profile.studyStage.flatMap(StudyStage.init(rawValue:)),
            proficiencySource: profile.proficiencySource.flatMap(ProficiencySource.init(rawValue:))
                ?? .selfReported,
            placementScore: profile.placementScore,
            placementCompletedAt: profile.placementCompletedAt.flatMap {
                try? parseDate($0)
            },
            hasCompletedProfileSetup: profile.hasCompletedProfileSetup ?? false
        )
    }

    /// 业务状态快照不包含计费权益，合并时保留 BillingKit 已验证的本地投影。
    private func mapPreservingEntitlement(
        _ profile: BackendUserProfile
    ) async -> UserProfileDTO {
        var mapped = map(profile)
        guard let cached = try? await economyCache.profile() else {
            return mapped
        }
        mapped.subscriptionTier = cached.subscriptionTier
        if cached.subscriptionTier != .free {
            mapped.friendSlotLimit = max(mapped.friendSlotLimit, cached.friendSlotLimit)
        }
        return mapped
    }

    private func map(_ ticket: BackendTicket) throws -> ItemDTO {
        let type: ItemType
        switch ticket.type {
        case "universal": type = .ticketUniversal
        case "country": type = .ticketCountry
        default: throw BackendClientError.invalidResponse
        }
        guard let source = ItemSource(rawValue: ticket.source) else {
            throw BackendClientError.invalidResponse
        }
        return ItemDTO(
            id: ticket.id,
            type: type,
            countryCode: ticket.countryCode,
            source: source,
            createdAt: try parseDate(ticket.createdAt),
            consumedAt: nil
        )
    }

    private func parseDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw BackendClientError.invalidResponse
        }
        return date
    }

    private nonisolated static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
