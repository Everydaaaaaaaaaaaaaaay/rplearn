#if DEBUG
import DomainKit
import Foundation
import LLMKit

actor DebugGrammarAnalysisFixture {
    static let shared = DebugGrammarAnalysisFixture()
    private var calls = 0
    func analyze(sentence: String, level: String) async throws -> AIGrammarAnalysis {
        calls += 1
        try await Task.sleep(for: .milliseconds(250))
        if ProcessInfo.processInfo.environment["UI_TEST_GRAMMAR_FIXTURE"] == "retry", calls == 1 {
            throw LLMError.http(status: 503, message: "Temporary test failure")
        }
        return .init(summaryZh: "这是口语中常见的感叹省略。", points: [
            .init(title: "感叹句中的省略", quote: sentence, pattern: "Adjective!",
                  explanationZh: "口语可以用形容词单独表达赞叹。", learnerTipZh: "完整说法是 That is amazing!。")
        ])
    }
}
#endif
