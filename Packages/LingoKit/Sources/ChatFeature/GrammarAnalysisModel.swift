import DomainKit
import Foundation
import Observation

@MainActor @Observable
final class GrammarAnalysisModel {
    var source: GrammarAnalysisSource = .local
    private(set) var analysis: AIGrammarAnalysis?
    private(set) var isLoading = false
    private(set) var error: String?
    var retryRevision = 0
    private var generation = UUID()

    init(analysis: AIGrammarAnalysis? = nil) { self.analysis = analysis }

    func load(using operation: @Sendable () async throws -> AIGrammarAnalysis) async -> AIGrammarAnalysis? {
        guard source == .ai, analysis == nil else { return nil }
        let token = UUID()
        generation = token
        isLoading = true
        error = nil
        defer { if generation == token { isLoading = false } }
        do {
            let result = try await operation()
            try Task.checkCancellation()
            guard generation == token, source == .ai else { return nil }
            analysis = result
            return result
        } catch {
            guard generation == token, !Task.isCancelled,
                  !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return nil }
            self.error = GrammarAnalysisErrorPresentation.message(for: error)
            return nil
        }
    }
}
