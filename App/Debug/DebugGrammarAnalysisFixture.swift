#if DEBUG
import BackendKit
import DomainKit
import Foundation

actor DebugGrammarAnalysisFixture {
    static let shared = DebugGrammarAnalysisFixture()
    private var calls = 0
    private var firstOperationID: UUID?
    func analyze(sentence: String, operationID: UUID) async throws -> AIGrammarAnalysis {
        calls += 1
        try await Task.sleep(for: .milliseconds(250))
        let mode = ProcessInfo.processInfo.environment["UI_TEST_GRAMMAR_FIXTURE"]
        if calls == 1 {
            firstOperationID = operationID
            if mode == "retry" { throw BackendClientError.transport("Temporary test failure") }
            if mode == "invalid-output" {
                throw BackendClientError.api(code: "GRAMMAR_INVALID_OUTPUT", message: "Invalid output", requestID: nil, status: 502)
            }
            if mode == "manual" {
                throw BackendClientError.api(code: "AI_RATE_LIMIT_EXCEEDED", message: "Rate limited", requestID: nil, status: 429)
            }
        }
        if calls == 2, mode == "retry", firstOperationID != operationID { throw BackendClientError.invalidResponse }
        if calls == 2, mode == "invalid-output", firstOperationID == operationID { throw BackendClientError.invalidResponse }
        return .init(summaryZh: "这是口语中常见的感叹省略。", points: [
            .init(title: "感叹句中的省略", quote: sentence, pattern: "Adjective!",
                  explanationZh: "口语可以用形容词单独表达赞叹。", learnerTipZh: "完整说法是 That is amazing!。")
        ])
    }
}
#endif
