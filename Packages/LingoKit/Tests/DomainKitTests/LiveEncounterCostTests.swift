import DomainKit
import Foundation
import LLMKit
import PersistenceKit
import Testing

/// Explicit paid experiment only. A loopback bridge holds provider credentials server-side.
@Suite("相遇费用对照", .enabled(if: FileManager.default.fileExists(atPath: "/tmp/lingotrip-encounter-cost-enabled")))
struct LiveEncounterCostTests {
    @Test
    func compare() async throws {
        let card = CharacterCard(name: "Dev Singh", age: 34, gender: .male, nationality: "British",
            regionID: "london", occupation: "bicycle mechanic", hobbies: ["修理自行车", "逛旧货市场"],
            appearance: "", personality: "practical, candid and calm")
        let context = "城市：伦敦。公园小憩 · 喝口咖啡。你端起咖啡喝了一口。附近也有人停下来看向远处的桥，你们恰好在看同一处风景。"
        var outcomes: [[String: String]] = []
        let diagnostic = (try? String(contentsOfFile: "/tmp/lingotrip-encounter-cost-enabled", encoding: .utf8))?.contains("diagnostic") == true
        let labels = diagnostic ? ["old-diagnostic-1", "new-diagnostic-1", "new-diagnostic-2", "old-diagnostic-2"]
            : ["old-1", "new-1", "new-2", "old-2", "old-3", "new-3"]
        for label in labels {
            let llm = MockLLMProvider(completeHandler: { request in
                // Exactly the schema-prefix serialization used by BackendLLMProvider.makeBody.
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                var system = request.system ?? ""
                if case .jsonSchema(let name, let schema) = request.responseFormat {
                    let schemaText = String(decoding: try encoder.encode(schema), as: UTF8.self)
                    system = "Return only one JSON object matching schema \"\(name)\". Do not add Markdown or explanation.\nJSON Schema:\n\(schemaText)\n\n" + system
                }
                var messages: [[String: String]] = [["role": "system", "content": system]]
                messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
                var http = URLRequest(url: URL(string: "http://127.0.0.1:18767")!)
                http.httpMethod = "POST"; http.timeoutInterval = 75
                http.setValue("application/json", forHTTPHeaderField: "Content-Type")
                http.httpBody = try JSONSerialization.data(withJSONObject: ["label": label, "messages": messages, "maxTokens": request.maxTokens])
                let (data, response) = try await URLSession.shared.data(for: http)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                return object["content"] as? String ?? ""
            })
            let service = SocialDialogueService(llm: llm)
            do {
                if label.hasPrefix("new") {
                    _ = try await service.plan(card: card, context: context, history: "", alreadyKnown: false, difficulty: .junior3)
                } else {
                    let opening = try await service.reply(card: card, context: context, history: "", userLine: nil,
                        invitesContact: false, alreadyKnown: false, difficulty: .junior3)
                    var history = "\nassistant: \(opening.english)"
                    let user = "The view is lovely from here, isn't it?"
                    let first = try await service.reply(card: card, context: context, history: history, userLine: user,
                        invitesContact: false, alreadyKnown: false, difficulty: .junior3)
                    history += "\nuser: \(user)\nassistant: \(first.english)"
                    _ = try await service.reply(card: card, context: context, history: history,
                        userLine: "Would you like to keep in touch?", invitesContact: true, alreadyKnown: false, difficulty: .junior3)
                }
                outcomes.append(["label": label, "status": "complete"])
            } catch {
                outcomes.append(["label": label, "status": "failed", "error": String(describing: error)])
            }
        }
        try JSONSerialization.data(withJSONObject: outcomes, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: "/tmp/lingotrip-encounter-cost-outcomes\(diagnostic ? "-diagnostic" : "").json"))
    }
}
