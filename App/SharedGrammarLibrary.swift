import BackendKit
import DictKit
import DomainKit
import Foundation
import LLMKit

private struct SharedGrammarCatalog: Decodable, Sendable {
    let points: [GrammarPoint]
}
private struct SharedGrammarResponse: Decodable, Sendable {
    let analysis: AIGrammarAnalysis
    let learnedPoints: [GrammarPoint]
}
private struct GrammarRequestBody: Encodable, Sendable {
    let sentence: String
    let learnerLevel: String
    let operationId = UUID()
}

extension AppEnvironment {
    var sharedGrammarAnalyzer: @Sendable (String, String) async throws -> AIGrammarAnalysis {
        let backend = backendClient, grammar = grammarPoints, llm = llmRouter
        return { sentence, level in
            do {
                let response: SharedGrammarResponse = try await backend.send(path: "/v1/grammar/analysis", method: "POST",
                    body: GrammarRequestBody(sentence: sentence, learnerLevel: level))
                grammar.mergeSharedPoints(response.learnedPoints)
                return response.analysis
            } catch BackendClientError.api(_, _, _, let status) where status == 404 {
                // A rollback to the compatible server keeps analysis available.
                return try await GrammarAnalysisService(llm: llm).analyze(sentence: sentence, learnerLevel: level)
            } catch BackendClientError.api(_, let message, _, let status) {
                throw LLMError.http(status: status, message: message)
            } catch BackendClientError.signedOut {
                throw LLMError.http(status: 401, message: "Signed out")
            } catch BackendClientError.invalidResponse {
                throw LLMError.invalidResponse("Invalid shared grammar response")
            } catch BackendClientError.transport {
                throw URLError(.cannotConnectToHost)
            }
        }
    }

    func refreshSharedGrammarLibrary() async {
        guard onboardingPreviewMode == nil, resourcesReady else { return }
        do {
            let catalog: SharedGrammarCatalog = try await backendClient.publicGet("/v1/grammar/catalog")
            let grammar = grammarPoints
            await Task.detached(priority: .utility) { grammar.mergeSharedPoints(catalog.points) }.value
        } catch { /* Bundled and previously downloaded rules stay available offline. */ }
    }
}
