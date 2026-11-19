import Foundation
import PersistenceKit

public struct MemoryFact: Codable, Sendable, Equatable {
    public var key: String
    public var text: String
    public var status: String
    public var evidence: String
    public var eventDate: String?

    /// Cheap gate: ordinary greetings never grow the joint-review prompt.
    /// Periodic summaries remain the fallback for facts this conservative gate misses.
    public static func shouldExtract(_ text: String) -> Bool {
        let patterns = [
            #"\b(my name|my birthday|my dog|my cat|my job|my partner|i live|i work|i like|i prefer|i love|i hate|i used to|i no longer|i don't|i do not|i plan|i will|i promised|i promise|i am going to|i'm going to|i was wrong|i said it wrong|i meant(?!\s+to\b)|more specifically|to be more specific|to be precise|allergic|allergy|favourite|favorite|appointment|interview|graduated|married|moved|cancelled|canceled|rescheduled|remember that)\b|\bcorrection\s*:"#,
            #"我喜欢|我不再|我住|我叫|我的生日|我的工作|我打算|我计划|过敏|改到|取消|面试|记住|我不喜欢|我说错了|更正一下|更具体地说|准确来说"#
        ]
        return text.count >= 8 && patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    public func record(from message: MessageDTO) -> MemoryRecord? {
        let quote = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        let factText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.role == .user, quote.count >= 4, quote.contains(where: \.isLetter),
              message.text.range(of: quote, options: [.caseInsensitive, .literal]) != nil,
              factText.contains(where: { $0.isLetter || $0.isNumber }), factText.count <= 240, key.count <= 64,
              key.range(of: #"^user\.[a-z0-9_.-]+$"#, options: .regularExpression) != nil,
              ["active", "planned", "completed", "cancelled"].contains(status) else { return nil }
        // Resolve explicit ISO dates and today/tomorrow against the source timestamp.
        var resolvedText = factText
        var date = eventDate.flatMap {
            $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
                && message.text.contains($0) ? $0 : nil
        }
        if date == nil {
            for (word, offset) in [("tomorrow", 1), ("today", 0)] where quote.localizedCaseInsensitiveContains(word) {
                let calendar = Calendar.current
                if let day = calendar.date(byAdding: .day, value: offset, to: message.createdAt) {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = calendar.timeZone
                    formatter.dateFormat = "yyyy-MM-dd"
                    date = formatter.string(from: day)
                    resolvedText = resolvedText.replacingOccurrences(of: word, with: date!, options: .caseInsensitive)
                }
                break
            }
        }
        return MemoryRecord(key: key, text: resolvedText, status: status, evidence: String(quote.prefix(240)),
            messageID: message.id, observedAt: message.createdAt, eventDate: date)
    }
}
