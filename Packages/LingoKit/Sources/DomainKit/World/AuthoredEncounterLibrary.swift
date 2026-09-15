import Foundation

/// Versioned, bundled stories. Reading or choosing a branch never calls a model.
public struct AuthoredEncounterLibrary: Sendable {
    public struct Entry: Decodable, Sendable {
        public let id: UUID
        public let story: Story
        public let reunion: Reunion
    }
    public struct Story: Decodable, Sendable {
        public let titleZh: String
        public let actionId: String
        public let nodes: [Node]
    }
    public struct Node: Decodable, Sendable {
        public struct Choice: Decodable, Sendable {
            public let english: String
            public let chinese: String
            public let next: String
        }
        public let id: String
        public let beats: [EncounterChapter.Beat]
        public let choices: [Choice]
    }
    public struct Reunion: Decodable, Sendable {
        public let titleZh: String
        public let beats: [EncounterChapter.Beat]
    }
    private struct Manifest: Decodable {
        let version: Int
        let libraryVersion: String
        let entries: [Entry]
    }
    public enum LibraryError: Error { case missingBundle, invalidContent, unavailableCharacter, invalidChoice }
    public let version: String
    public let entries: [UUID: Entry]

    public init(data: Data) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.version == 1, !manifest.libraryVersion.isEmpty,
              manifest.entries.count == 200, Set(manifest.entries.map(\.id)).count == 200 else {
            throw LibraryError.invalidContent
        }
        for entry in manifest.entries {
            let expected = ["start": ["a", "b"], "a": ["aa", "ab"], "b": ["ba", "bb"],
                            "aa": [], "ab": [], "ba": [], "bb": []]
            guard !entry.story.titleZh.isEmpty, !entry.reunion.titleZh.isEmpty,
                  entry.story.nodes.first(where: { $0.id == "start" })?.beats.first?.speaker == "narrator",
                  entry.reunion.beats.first?.speaker == "narrator",
                  Set(entry.story.nodes.map(\.id)) == Set(expected.keys), entry.story.nodes.count == 7 else {
                throw LibraryError.invalidContent
            }
            for node in entry.story.nodes {
                guard node.choices.map(\.next) == expected[node.id],
                      node.choices.allSatisfy({ !$0.english.isEmpty && !$0.chinese.isEmpty }) else {
                    throw LibraryError.invalidContent
                }
                try Self.validate(node.beats)
            }
            try Self.validate(entry.reunion.beats)
        }
        version = manifest.libraryVersion
        entries = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.id, $0) })
    }

    private static let englishTitles: [String: String] = {
        guard let url = Bundle.main.url(forResource: "npc-encounter-titles-en", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let titles = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return titles
    }()

    private static let bundledResult: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "npc-library-v3", withExtension: "json") else {
            throw LibraryError.missingBundle
        }
        return try Self(data: Data(contentsOf: url))
    }
    public static func bundled() throws -> Self { try bundledResult.get() }

    public func chapter(characterID: UUID, actionID: String, choices: [Int], reunion: Bool = false) throws -> EncounterChapter {
        guard let entry = entries[characterID], entry.story.actionId == actionID else { throw LibraryError.unavailableCharacter }
        if reunion {
            guard choices.isEmpty else { throw LibraryError.invalidChoice }
            return EncounterChapter(title: entry.reunion.titleZh, outline: entry.reunion.titleZh,
                                    beats: entry.reunion.beats, choices: [], titleEnglish: Self.englishTitles[entry.reunion.titleZh])
        }
        guard choices.count <= 2 else { throw LibraryError.invalidChoice }
        let nodes = Dictionary(uniqueKeysWithValues: entry.story.nodes.map { ($0.id, $0) })
        var key = "start"
        for index in choices {
            guard let node = nodes[key], node.choices.indices.contains(index) else { throw LibraryError.invalidChoice }
            key = node.choices[index].next
        }
        guard let node = nodes[key] else { throw LibraryError.invalidContent }
        return EncounterChapter(title: entry.story.titleZh, outline: entry.story.titleZh, beats: node.beats,
                                choices: node.choices.map { .init(english: $0.english, chinese: $0.chinese) },
                                titleEnglish: Self.englishTitles[entry.story.titleZh])
    }

    private static func validate(_ beats: [EncounterChapter.Beat]) throws {
        guard (4...6).contains(beats.count), beats.filter({ $0.speaker == "npc" }).count >= 2,
              beats.contains(where: { $0.speaker == "narrator" }),
              beats.allSatisfy({ ["npc", "narrator"].contains($0.speaker)
                  && !$0.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && !$0.chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && $0.english.count <= 420 && $0.chinese.count <= 260 }) else {
            throw LibraryError.invalidContent
        }
    }
}
