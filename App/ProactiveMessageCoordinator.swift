import ChatFeature
import CoreKit
import DomainKit
import Foundation
import LLMKit
import PersistenceKit
import UserNotifications

extension Notification.Name {
    static let proactiveMessagesDidChange = Notification.Name("LingoTripProactiveMessagesDidChange")
    static let didOpenProactiveMessage = Notification.Name("LingoTripDidOpenProactiveMessage")
}

enum ProactiveMessageRoute {
    private static let pendingKey = "lingotrip.proactive.open-messages"

    static func recordNotificationTap() {
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    static func consumeNotificationTap() -> Bool {
        let shouldOpen = UserDefaults.standard.bool(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return shouldOpen
    }
}

/// 端内主动消息编排。
///
/// App 活跃时预生成少量未来消息并交给 iOS 定时提醒；到期后再次打开 App，
/// 同一个事件才会幂等写入聊天记录，因此不需要常驻后台服务或推送证书。
@MainActor
final class ProactiveMessageCoordinator {
    private struct PendingMessage: Codable, Equatable, Identifiable {
        let id: UUID
        let characterID: UUID
        let characterName: String
        let text: String
        let dueAt: Date

        var notificationIdentifier: String {
            "\(ProactiveMessageCoordinator.notificationPrefix)\(id.uuidString.lowercased())"
        }
    }

    private nonisolated static let notificationPrefix = "lingotrip.proactive."
    private static let pendingKeyPrefix = "lingotrip.proactive.pending."
    private static let unreadCountKey = "lingotrip.unread.count"

    private let rosterStore: RosterStore
    private let chatStore: ChatStore
    private let economyStore: EconomyStore
    private let messageService: ProactiveMessageService
    private let notificationCenter: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var scope = "guest"
    private var isRefreshing = false

    init(
        rosterStore: RosterStore,
        chatStore: ChatStore,
        economyStore: EconomyStore,
        llm: any LLMClient,
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.rosterStore = rosterStore
        self.chatStore = chatStore
        self.economyStore = economyStore
        self.messageService = ProactiveMessageService(llm: llm)
        self.notificationCenter = notificationCenter
        self.defaults = defaults
    }

    func activate(scope: String, requestAuthorization: Bool) async {
        if self.scope != scope {
            self.scope = scope
            await removeScheduledNotifications()
        }
        await refresh(requestAuthorization: requestAuthorization)
    }

    func refresh(requestAuthorization: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard ProactiveMessagePreferences.isEnabled else {
            savePending([])
            await removeScheduledNotifications()
            return
        }

        var pending = loadPending()
        let learner = await currentLearnerContext()
        let materialized = await materializeDueMessages(in: &pending)
        let opened = await ensureInitialMessages(learner: learner)
        pending = await fillSchedule(pending, learner: learner)
        savePending(pending)

        let settings = await notificationCenter.notificationSettings()
        if requestAuthorization, settings.authorizationStatus == .notDetermined {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await scheduleNotifications(for: pending)

        if materialized || opened {
            NotificationCenter.default.post(name: .proactiveMessagesDidChange, object: nil)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        ProactiveMessagePreferences.isEnabled = enabled
        if enabled {
            await refresh(requestAuthorization: true)
        } else {
            savePending([])
            await removeScheduledNotifications()
        }
    }

    private func ensureInitialMessages(learner: LearnerContext) async -> Bool {
        guard let friends = try? await rosterStore.friends() else { return false }
        var insertedAny = false
        for character in friends {
            guard (try? await chatStore.needsInitialMessage(characterID: character.id)) == true else {
                continue
            }
            let text = await messageService.generate(
                for: character,
                learner: learner,
                occasion: .introduction
            )
            if (try? await chatStore.appendInitialMessageIfNeeded(
                characterID: character.id,
                text: text
            )) != nil {
                insertedAny = true
            }
        }
        return insertedAny
    }

    private func materializeDueMessages(in pending: inout [PendingMessage]) async -> Bool {
        let now = Date.now
        var remaining: [PendingMessage] = []
        var materializedIDs: [String] = []
        var insertedAny = false

        for message in pending.sorted(by: { $0.dueAt < $1.dueAt }) {
            guard message.dueAt <= now else {
                remaining.append(message)
                continue
            }
            guard let character = try? await rosterStore.character(id: message.characterID),
                  character.isFriend
            else {
                materializedIDs.append(message.notificationIdentifier)
                continue
            }
            do {
                let inserted = try await chatStore.appendProactiveMessageIfNeeded(
                    messageID: message.id,
                    characterID: message.characterID,
                    text: message.text
                )
                insertedAny = insertedAny || inserted != nil
                materializedIDs.append(message.notificationIdentifier)
            } catch {
                remaining.append(message)
            }
        }

        pending = remaining
        if !materializedIDs.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: materializedIDs)
            notificationCenter.removeDeliveredNotifications(withIdentifiers: materializedIDs)
        }
        return insertedAny
    }

    private func fillSchedule(
        _ existing: [PendingMessage],
        learner: LearnerContext
    ) async -> [PendingMessage] {
        guard var friends = try? await rosterStore.friends(), !friends.isEmpty else { return [] }
        var pending = existing
            .sorted { $0.dueAt < $1.dueAt }
        friends.shuffle()

        while pending.count < ProactiveMessageSchedulePolicy.maximumPendingCount {
            let anchor = max(pending.last?.dueAt ?? .distantPast, .now)
            let isFirst = pending.isEmpty
            let dueAt = ProactiveMessageSchedulePolicy.nextDate(
                after: anchor,
                randomUnit: .random(in: 0...1),
                minimumHours: isFirst ? 36 : 48,
                maximumHours: isFirst ? 72 : 96
            )
            let previousCharacterID = pending.last?.characterID
            let candidates = friends.filter { $0.id != previousCharacterID }
            guard let character = (candidates.isEmpty ? friends : candidates).randomElement() else { break }
            let recentMessages = await recentMessages(for: character.id)
            let text = await messageService.generate(
                for: character,
                learner: learner,
                occasion: .checkIn,
                recentMessages: recentMessages
            )
            pending.append(
                PendingMessage(
                    id: UUID(),
                    characterID: character.id,
                    characterName: character.card.name,
                    text: text,
                    dueAt: dueAt
                )
            )
        }
        return pending
    }

    private func currentLearnerContext() async -> LearnerContext {
        guard let profile = try? await economyStore.profile() else {
            return .fallback(difficulty: .junior3)
        }
        return LearnerContext(profile: profile)
    }

    private func recentMessages(for characterID: UUID) async -> [MessageDTO] {
        guard let summary = try? await chatStore.conversationSummaries()
            .first(where: { $0.characterID == characterID })
        else { return [] }
        return (try? await chatStore.messages(conversationID: summary.conversationID)) ?? []
    }

    private func scheduleNotifications(for pending: [PendingMessage]) async {
        await removeScheduledNotifications()
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
        else { return }

        let baseBadge = await currentUnreadCount()
        defaults.set(baseBadge, forKey: Self.unreadCountKey)
        for (index, message) in pending.sorted(by: { $0.dueAt < $1.dueAt }).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = message.characterName
            content.body = message.text
            content.sound = .default
            content.badge = NSNumber(value: baseBadge + index + 1)
            content.threadIdentifier = "character.\(message.characterID.uuidString.lowercased())"
            content.userInfo = [
                "kind": "proactive-message",
                "characterID": message.characterID.uuidString.lowercased(),
            ]
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: message.dueAt
            )
            let request = UNNotificationRequest(
                identifier: message.notificationIdentifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await notificationCenter.add(request)
        }
    }

    private func removeScheduledNotifications() async {
        let requests = await notificationCenter.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.notificationPrefix) }
        guard !identifiers.isEmpty else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func currentUnreadCount() async -> Int {
        guard let friends = try? await rosterStore.friends(),
              let summaries = try? await chatStore.conversationSummaries()
        else {
            return defaults.integer(forKey: Self.unreadCountKey)
        }
        return ConversationReadState.totalUnreadCount(
            friends: friends,
            summaries: summaries
        )
    }

    private var pendingKey: String {
        Self.pendingKeyPrefix + scope
    }

    private func loadPending() -> [PendingMessage] {
        guard let data = defaults.data(forKey: pendingKey) else { return [] }
        return (try? JSONDecoder().decode([PendingMessage].self, from: data)) ?? []
    }

    private func savePending(_ pending: [PendingMessage]) {
        if pending.isEmpty {
            defaults.removeObject(forKey: pendingKey)
        } else if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: pendingKey)
        }
    }
}
