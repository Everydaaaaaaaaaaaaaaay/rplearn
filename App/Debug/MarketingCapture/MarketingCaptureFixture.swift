#if DEBUG
import Foundation
import DomainKit
import PersistenceKit

extension AppEnvironment {
    /// Only called after creating the explicit in-memory UI-test workspace.
    /// Demonstration dialogue never reaches an account or an AI service.
    func seedMarketingCapture(into account: AccountWorkspace) async throws {
        _ = try await account.economyStore.updateProfile {
            $0.friendSlotLimit = 10
        }
        _ = try await account.itemStore.addTicket(type: .ticketUniversal, source: .story)
        _ = try await account.economyStore.addCoins(680)
        for (word, meaning) in [("shoreline", "海岸线"), ("cosy", "温暖舒适的")] {
            _ = try await account.favoritesStore.addWord(word, translationZh: meaning)
        }
        _ = try await account.favoritesStore.add(sentence: "Your brain deserves a day off.",
            sourceMessageID: nil, characterName: "Ruby Walker", translationZh: "你的大脑也该放一天假。")
        let url = Bundle.main.url(forResource: "npc-library-v3", withExtension: "json")!
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let entries = manifest["entries"] as! [[String: Any]]
        for (index, asset) in [(0, "tutorial-elliot"), (1, "marketing-victor"), (10, "marketing-mabel")] {
            var raw = entries[index]["card"] as! [String: Any]
            raw["regionID"] = raw.removeValue(forKey: "regionId")
            raw["avatarAssetName"] = asset
            let card = try JSONDecoder().decode(CharacterCard.self, from: JSONSerialization.data(withJSONObject: raw))
            _ = try await account.rosterStore.addCharacter(
                characterID: UUID(uuidString: entries[index]["id"] as! String)!,
                card: card, difficulty: .junior3, isFriend: true)
        }
        try await account.storyProgressStore.saveCheckpoint(storyID: "departures_london_v1", nodeID: "approach", flags: [:])
        let previews: [String: String] = [
            "Ruby Walker": "My latte art became a jellyfish 😂",
            "Oliver Bennett": "Arsenal won. Poetry can wait.",
            "Marcus Rivera": "Caught the light on film today.",
            "Elliot Shaw": "New jam. Terrible joke. Good day.",
            "Victor Lane": "Still know every ferry by its horn.",
            "Mabel Fenwick": "My tiny film has a dancing sock."
        ]
        let order = ["Ruby Walker", "Oliver Bennett", "Marcus Rivera", "Elliot Shaw", "Mabel Fenwick", "Victor Lane"]
        let characters = try await account.rosterStore.allCharacters()
        for character in characters.sorted(by: {
            (order.firstIndex(of: $0.card.name) ?? 99) > (order.firstIndex(of: $1.card.name) ?? 99)
        }) {
            guard let preview = previews[character.card.name], let index = order.firstIndex(of: character.card.name) else { continue }
            let conversation = try await account.chatStore.openConversation(characterID: character.id)
            // The Ruby conversation is newly seeded only when the older welcome fixture is not active.
            let capturesCoaches = ProcessInfo.processInfo.environment["UI_TEST_CAPTURE_COACHES"] == "1" && character.card.name == "Ruby Walker"
            let lines: [(MessageRole, String)] = capturesCoaches ? [
                (.assistant, "Tell me about your afternoon!"),
                (.user, "I go to a cosy café yesterday."),
                (.user, "I ordered two coffee for us."),
                (.assistant, "Now that’s a proper afternoon!")
            ] : character.card.name == "Ruby Walker" ? [
                (.user, "I finally finished my exams!"),
                (.assistant, "Yesss! Your brain deserves a day off 🌊"),
                (.user, "Exactly. I'm taking it easy today."),
                (.assistant, "What's your perfect way to unwind after a busy day?"),
                (.user, "A cosy café, a good book, and absolutely no alarm clocks."),
                (.assistant, "No alarm clocks? Now that's a proper holiday 😂"),
                (.user, "How did your latte art practice go?"),
                (.assistant, preview)
            ] : [(.user, "What's been the highlight of your day?"), (.assistant, preview)]
            for (lineIndex, line) in lines.enumerated() {
                if ProcessInfo.processInfo.environment["UI_TEST_MARKETING_MOTION"] == "1",
                   character.card.name == "Ruby Walker", lineIndex == lines.count - 1 { continue }
                // Stable IDs make both existing mascot variants reproducible in the capture.
                let captureID = capturesCoaches && line.0 == .user
                    ? UUID(uuidString: lineIndex == 1 ? "CA970000-0000-4000-8000-000000000000" : "CA970000-0000-4000-8000-000000000001")!
                    : UUID()
                let message = try await account.chatStore.appendMessage(messageID: captureID, conversationID: conversation.id, role: line.0,
                    text: line.1, createdAt: Date().addingTimeInterval(Double(-index * 180 - (lines.count - lineIndex) * 20)))
                if capturesCoaches && line.0 == .user {
                    let issue = lineIndex == 1
                        ? CoachReview.Issue(quote: "go", type: "grammar", correction: "went", explanationZh: "yesterday 表示过去，go 要用过去式 went。")
                        : CoachReview.Issue(quote: "two coffee", type: "grammar", correction: "two coffees", explanationZh: "两杯咖啡要用复数：two coffees。")
                    try await account.chatStore.setCoachReview(messageID: message.id, json: CoachService.encode(CoachReview(hasIssues: true, issues: [issue])))
                }
                if line.1 == "A cosy café, a good book, and absolutely no alarm clocks." {
                    _ = try await account.favoritesStore.addWord("cosy", sourceMessageID: message.id)
                }
            }
        }
    }
}
#endif
