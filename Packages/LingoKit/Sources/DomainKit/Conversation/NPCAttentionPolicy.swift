import Foundation
import PersistenceKit

public enum NPCPresenceState: String, Sendable, Codable, Equatable {
    case online
    case recentlyActive
    case offline
}

public enum NPCAttentionLevel: String, Sendable, Codable, Equatable {
    case focused
    case online
    case recentlyActive
    case offline
}

public struct NPCPresenceSnapshot: Sendable, Equatable {
    public let state: NPCPresenceState
    public let lastActiveAt: Date?
    public let timeZoneIdentifier: String

    public init(
        state: NPCPresenceState,
        lastActiveAt: Date?,
        timeZoneIdentifier: String
    ) {
        self.state = state
        self.lastActiveAt = lastActiveAt
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// 一次用户消息对应的稳定时序。所有日期都由消息 ID 确定性生成，重启后不会重新抽取。
public struct NPCReplyPlan: Sendable, Equatable {
    public let userMessageID: UUID
    public let attention: NPCAttentionLevel
    public let noticedAt: Date
    public let generationStartsAt: Date
    public let typingStartsAt: Date
    public let firstBubbleAt: Date
    public let continuingConversation: Bool

    public init(
        userMessageID: UUID,
        attention: NPCAttentionLevel,
        noticedAt: Date,
        generationStartsAt: Date,
        typingStartsAt: Date,
        firstBubbleAt: Date,
        continuingConversation: Bool = false
    ) {
        self.userMessageID = userMessageID
        self.attention = attention
        self.noticedAt = noticedAt
        self.generationStartsAt = generationStartsAt
        self.typingStartsAt = typingStartsAt
        self.firstBubbleAt = firstBubbleAt
        self.continuingConversation = continuingConversation
    }
}

/// NPC 作息、注意力续期与首条气泡时序的统一规则。
public struct NPCAttentionPolicy: Sendable {
    public static let standard = NPCAttentionPolicy()

    public let focusedReplyRange: ClosedRange<TimeInterval>
    public let onlineReplyRange: ClosedRange<TimeInterval>
    public let recentlyActiveReplyRange: ClosedRange<TimeInterval>
    public let offlineReplyRange: ClosedRange<TimeInterval>

    public init(
        focusedReplyRange: ClosedRange<TimeInterval> = 3...7,
        onlineReplyRange: ClosedRange<TimeInterval> = 8...22,
        recentlyActiveReplyRange: ClosedRange<TimeInterval> = 20...45,
        offlineReplyRange: ClosedRange<TimeInterval> = 60...300
    ) {
        self.focusedReplyRange = focusedReplyRange
        self.onlineReplyRange = onlineReplyRange
        self.recentlyActiveReplyRange = recentlyActiveReplyRange
        self.offlineReplyRange = offlineReplyRange
    }

    public func replyPlan(
        for character: CharacterDTO,
        userMessage: MessageDTO,
        history: [MessageDTO]
    ) -> NPCReplyPlan {
        let profile = activityProfile(for: character)
        let previousAssistant = history.last {
            $0.role == .assistant && $0.orderIndex < userMessage.orderIndex
        }
        let focusDuration = TimeInterval(
            min(max(profile.focusDurationMinutes, 4), 12) * 60
        )
        let isFocused = previousAssistant.map {
            let elapsed = userMessage.createdAt.timeIntervalSince($0.createdAt)
            return elapsed >= 0 && elapsed <= focusDuration
        } ?? false

        let attention: NPCAttentionLevel
        if isFocused || isNewEncounterOnline(character, at: userMessage.createdAt) {
            attention = .focused
        } else {
            attention = switch scheduledPresence(
                for: character,
                at: userMessage.createdAt,
                profile: profile
            ).state {
            case .online: .online
            case .recentlyActive: .recentlyActive
            case .offline: .offline
            }
        }
        return makeReplyPlan(
            attention: attention,
            userMessageID: userMessage.id,
            sentAt: userMessage.createdAt,
            continuingConversation: isFocused
        )
    }

    /// 用户主动重试被中断的回复时，不再次模拟离开手机的等待。
    public func expeditedReplyPlan(
        userMessageID: UUID,
        sentAt: Date,
        delay: TimeInterval
    ) -> NPCReplyPlan {
        let firstBubbleAt = sentAt.addingTimeInterval(max(0, delay))
        return NPCReplyPlan(
            userMessageID: userMessageID,
            attention: .focused,
            noticedAt: sentAt,
            generationStartsAt: sentAt,
            typingStartsAt: sentAt,
            firstBubbleAt: firstBubbleAt
        )
    }

    public func presence(
        for character: CharacterDTO,
        at date: Date,
        lastAssistantMessageAt: Date?,
        pendingReplyPlan: NPCReplyPlan?
    ) -> NPCPresenceSnapshot {
        let profile = activityProfile(for: character)
        let timeZoneIdentifier = profile.timeZoneIdentifier

        if isNewEncounterOnline(character, at: date) {
            return NPCPresenceSnapshot(state: .online, lastActiveAt: date,
                timeZoneIdentifier: timeZoneIdentifier)
        }

        if let lastAssistantMessageAt {
            let focusDuration = TimeInterval(
                min(max(profile.focusDurationMinutes, 4), 12) * 60
            )
            let elapsed = date.timeIntervalSince(lastAssistantMessageAt)
            if elapsed >= 0, elapsed <= focusDuration {
                return NPCPresenceSnapshot(
                    state: .online,
                    lastActiveAt: date,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
        }

        if let pendingReplyPlan {
            if date >= pendingReplyPlan.noticedAt {
                return NPCPresenceSnapshot(
                    state: .online,
                    lastActiveAt: date,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
            switch pendingReplyPlan.attention {
            case .focused, .online:
                return NPCPresenceSnapshot(
                    state: .online,
                    lastActiveAt: date,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            case .recentlyActive:
                let scheduled = scheduledPresence(for: character, at: date, profile: profile)
                return NPCPresenceSnapshot(
                    state: .recentlyActive,
                    lastActiveAt: scheduled.lastActiveAt,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            case .offline:
                let scheduled = scheduledPresence(for: character, at: date, profile: profile)
                return NPCPresenceSnapshot(
                    state: .offline,
                    lastActiveAt: scheduled.lastActiveAt,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
        }

        return scheduledPresence(for: character, at: date, profile: profile)
    }

    public func activityProfile(for character: CharacterDTO) -> NPCActivityProfile {
        Self.activityProfile(for: character.card)
    }

    public static func activityProfile(for card: CharacterCard) -> NPCActivityProfile {
        if let explicit = card.activityProfile,
           TimeZone(identifier: explicit.timeZoneIdentifier) != nil {
            return explicit
        }
        let identityText = [
            card.occupation,
            card.personality,
            card.background ?? "",
        ]
        .joined(separator: " ")
        .lowercased()
        let rhythm: NPCActivityRhythm
        let nightSignals = [
            "night", "late", "jazz", "club", "bartender", "pub", "夜", "酒吧", "夜班", "爵士",
        ]
        let earlySignals = [
            "barista", "bakery", "teacher", "farmer", "surf", "咖啡师", "烘焙", "教师", "农", "冲浪",
        ]
        let words = Set(identityText.split { !$0.isLetter }.map(String.init))
        func matches(_ signal: String) -> Bool {
            signal.allSatisfy(\.isASCII) ? words.contains(signal) : identityText.contains(signal)
        }
        if nightSignals.contains(where: matches) {
            rhythm = .nightOwl
        } else if earlySignals.contains(where: matches) {
            rhythm = .earlyBird
        } else {
            rhythm = .daytime
        }
        return Self.defaultActivityProfile(regionID: card.regionID, rhythm: rhythm)
    }

    public static func defaultActivityProfile(
        regionID: String,
        rhythm: NPCActivityRhythm,
        focusDurationMinutes: Int = 7
    ) -> NPCActivityProfile {
        NPCActivityProfile(
            timeZoneIdentifier: timeZoneIdentifier(for: regionID),
            rhythm: rhythm,
            focusDurationMinutes: focusDurationMinutes
        )
    }

    public static func timeZoneIdentifier(for regionID: String) -> String {
        RoleplayTemporalContext.timeZone(for: regionID).identifier
    }

    func makeReplyPlan(
        attention: NPCAttentionLevel,
        userMessageID: UUID,
        sentAt: Date,
        continuingConversation: Bool = false
    ) -> NPCReplyPlan {
        let range = switch attention {
        case .focused: focusedReplyRange
        case .online: onlineReplyRange
        case .recentlyActive: recentlyActiveReplyRange
        case .offline: offlineReplyRange
        }
        let firstDelay = sampledDuration(
            in: range,
            messageID: userMessageID,
            salt: "first-bubble",
            biasesEarlier: attention == .offline
        )
        let firstBubbleAt = sentAt.addingTimeInterval(firstDelay)
        let typingLeadRange: ClosedRange<TimeInterval> = switch attention {
        case .focused: 1.2...2.8
        case .online: 2...4.5
        case .recentlyActive, .offline: 2.5...6
        }
        let typingLead = min(
            sampledDuration(
                in: typingLeadRange,
                messageID: userMessageID,
                salt: "typing-lead"
            ),
            max(0.8, firstDelay - 0.5)
        )
        // Only a recent actual reply establishes conversational attention. The
        // welcome-online window alone must retain the existing first-turn pacing.
        let typingStartsAt = continuingConversation
            ? sentAt.addingTimeInterval(sampledDuration(
                in: 2...3, messageID: userMessageID, salt: "focused-typing-start"
            ))
            : firstBubbleAt.addingTimeInterval(-typingLead)
        let deliveryAt = continuingConversation
            ? max(firstBubbleAt, typingStartsAt.addingTimeInterval(typingLead))
            : firstBubbleAt

        let noticedAt: Date
        switch attention {
        case .focused, .online:
            noticedAt = sentAt
        case .recentlyActive, .offline:
            let preparationTime = sampledDuration(
                in: 1.2...4.5,
                messageID: userMessageID,
                salt: "noticed"
            )
            noticedAt = max(
                sentAt,
                typingStartsAt.addingTimeInterval(-preparationTime)
            )
        }

        let generationCandidate: Date = switch attention {
        case .focused:
            sentAt.addingTimeInterval(min(1.2, firstDelay * 0.3))
        case .online:
            sentAt.addingTimeInterval(min(3.2, firstDelay * 0.35))
        case .recentlyActive, .offline:
            noticedAt.addingTimeInterval(0.2)
        }
        let generationStartsAt = min(
            generationCandidate,
            typingStartsAt.addingTimeInterval(-0.2)
        )
        return NPCReplyPlan(
            userMessageID: userMessageID,
            attention: attention,
            noticedAt: noticedAt,
            generationStartsAt: max(noticedAt, generationStartsAt),
            typingStartsAt: typingStartsAt,
            firstBubbleAt: deliveryAt,
            continuingConversation: continuingConversation
        )
    }

    func scheduledPresence(
        for character: CharacterDTO,
        at date: Date,
        profile: NPCActivityProfile? = nil
    ) -> NPCPresenceSnapshot {
        let profile = profile ?? activityProfile(for: character)
        // Jitter each boundary independently. Adjacent windows remain ordered
        // (6–54 minutes), and rebuilding the same date never rerolls presence.
        var bucket = Int(floor(date.timeIntervalSince1970 / 1800))
        while boundary(character.id, bucket: bucket) > date { bucket -= 1 }
        while boundary(character.id, bucket: bucket + 1) <= date { bucket += 1 }
        if isScheduledOnline(characterID: character.id,
                             at: boundary(character.id, bucket: bucket), profile: profile) {
            return NPCPresenceSnapshot(state: .online, lastActiveAt: date,
                timeZoneIdentifier: profile.timeZoneIdentifier)
        }
        var lastActiveAt: Date?
        for offset in 1...96 {
            if isScheduledOnline(characterID: character.id,
                at: boundary(character.id, bucket: bucket - offset), profile: profile) {
                lastActiveAt = boundary(character.id, bucket: bucket - offset + 1)
                break
            }
        }
        let recentlyActive = lastActiveAt.map { date.timeIntervalSince($0) < 30 * 60 } ?? false
        return NPCPresenceSnapshot(state: recentlyActive ? .recentlyActive : .offline,
            lastActiveAt: lastActiveAt, timeZoneIdentifier: profile.timeZoneIdentifier)
    }

    private func boundary(_ id: UUID, bucket: Int) -> Date {
        Date(timeIntervalSince1970: Double(bucket) * 1800
             + (stableUnit(characterID: id, bucket: bucket, salt: "boundary") * 2 - 1) * 720)
    }

    /// Persisted meeting time provides a 20–35 minute welcome window, even at night.
    /// User messages do not extend it; actual replies renew the ordinary focus lease.
    private func isNewEncounterOnline(_ character: CharacterDTO, at date: Date) -> Bool {
        let duration = 1200 + stableUnit(characterID: character.id,
            bucket: Int(character.metAt.timeIntervalSince1970), salt: "welcome") * 900
        return (0...duration).contains(date.timeIntervalSince(character.metAt))
    }

    func onlineProbability(
        rhythm: NPCActivityRhythm,
        localHour: Double,
        isWeekend: Bool
    ) -> Double {
        let probability: Double = switch rhythm {
        case .earlyBird:
            switch localHour {
            case 0..<5: 0.02
            case 5..<7: 0.18
            case 7..<12: 0.68
            case 12..<18: 0.58
            case 18..<22: 0.32
            default: 0.07
            }
        case .daytime:
            switch localHour {
            case 0..<6: 0.025
            case 6..<9: 0.16
            case 9..<12: 0.58
            case 12..<14: 0.42
            case 14..<19: 0.66
            case 19..<23: 0.38
            default: 0.08
            }
        case .nightOwl:
            switch localHour {
            case 0..<2: 0.42
            case 2..<7: 0.045
            case 7..<11: 0.10
            case 11..<17: 0.40
            case 17..<21: 0.58
            default: 0.72
            }
        case .irregular:
            switch localHour {
            case 1..<6: 0.055
            case 6..<10: 0.22
            case 10..<18: 0.50
            case 18..<24: 0.54
            default: 0.18
            }
        }
        let weekendLift = isWeekend && localHour >= 9 && localHour < 24 ? 0.06 : 0
        return min(probability + weekendLift, 0.82)
    }

    private func isScheduledOnline(
        characterID: UUID,
        at bucket: Date,
        profile: NPCActivityProfile
    ) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: profile.timeZoneIdentifier)
            ?? TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: bucket)
        let localDay = Int(calendar.startOfDay(for: bucket).timeIntervalSince1970 / 86400)
        let dailyShift = (stableUnit(characterID: characterID, bucket: localDay, salt: "daily-rhythm") * 2 - 1)
        let hour = (Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
                    + dailyShift + 24).truncatingRemainder(dividingBy: 24)
        let weekday = components.weekday ?? 1
        let probability = onlineProbability(
            rhythm: profile.rhythm,
            localHour: hour,
            isWeekend: weekday == 1 || weekday == 7
        )
        let bucketNumber = Int(bucket.timeIntervalSince1970 / (30 * 60))
        return stableUnit(
            characterID: characterID,
            bucket: bucketNumber,
            salt: "presence"
        ) < probability
    }

    private func sampledDuration(
        in range: ClosedRange<TimeInterval>,
        messageID: UUID,
        salt: String,
        biasesEarlier: Bool = false
    ) -> TimeInterval {
        let first = stableUnit(characterID: messageID, bucket: 0, salt: "\(salt)-a")
        let second = stableUnit(characterID: messageID, bucket: 0, salt: "\(salt)-b")
        let centered = (first + second) / 2
        let fraction = biasesEarlier ? pow(centered, 1.65) : centered
        return range.lowerBound + (range.upperBound - range.lowerBound) * fraction
    }

    private func stableUnit(characterID: UUID, bucket: Int, salt: String) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(characterID.uuidString.lowercased())|\(bucket)|\(salt)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Double(hash % 1_000_001) / 1_000_000
    }

}
