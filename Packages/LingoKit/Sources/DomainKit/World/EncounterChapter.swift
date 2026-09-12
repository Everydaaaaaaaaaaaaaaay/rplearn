import Foundation
import LLMKit
import PersistenceKit

public struct EncounterChapter: Codable, Equatable, Sendable {
    public struct Beat: Codable, Equatable, Sendable {
        public let speaker: String
        public let english: String
        public let chinese: String
        public init(speaker: String, english: String, chinese: String) {
            self.speaker = speaker; self.english = english; self.chinese = chinese
        }
    }
    public struct Choice: Codable, Equatable, Sendable {
        public let english: String
        public let chinese: String
        public init(english: String, chinese: String) { self.english = english; self.chinese = chinese }
    }
    public let title: String
    public let outline: String
    public let beats: [Beat]
    public let choices: [Choice]

    public init(title: String, outline: String, beats: [Beat], choices: [Choice]) {
        self.title = title; self.outline = outline; self.beats = beats; self.choices = choices
    }

    public static func decode(_ text: String, stage: Int) throws -> Self {
        guard (0...2).contains(stage), let data = JSONExtractor.extractJSONData(from: text),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.title.count <= 80, !value.outline.isEmpty, value.outline.count <= 600,
              (4...6).contains(value.beats.count),
              value.beats.filter({ $0.speaker == "npc" }).count >= 2,
              value.choices.count == (stage == 2 ? 0 : 2)
        else { throw SocialDialogueService.DialogueError.invalidReply }
        for beat in value.beats {
            guard ["npc", "narrator"].contains(beat.speaker), Self.valid(beat.english, limit: 420),
                  Self.valid(beat.chinese, limit: 260), beat.english.split(whereSeparator: \.isWhitespace).count <= 70
            else { throw SocialDialogueService.DialogueError.invalidReply }
        }
        for choice in value.choices {
            guard Self.valid(choice.english, limit: 180), Self.valid(choice.chinese, limit: 100)
            else { throw SocialDialogueService.DialogueError.invalidReply }
        }
        if value.choices.count == 2, value.choices[0].english == value.choices[1].english {
            throw SocialDialogueService.DialogueError.invalidReply
        }
        return value
    }
    private static func valid(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= limit && !value.contains("```")
    }
}
