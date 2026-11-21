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
    let operationId: UUID
}

enum SharedGrammarRequest {
    static func analyze(
        using send: @Sendable (UUID) async throws -> AIGrammarAnalysis
    ) async throws -> AIGrammarAnalysis {
        let operationID = UUID()
        do {
            return try await send(operationID)
        } catch let error as BackendClientError {
            let retryID: UUID
            switch error {
            case .transport, .api("OPERATION_IN_PROGRESS", _, _, _):
                // The first request may have reached the server. Reuse its credit operation.
                retryID = operationID
            case .api(let code, _, _, _):
                switch code {
                case "GRAMMAR_INVALID_OUTPUT", "AI_EMPTY_RESPONSE", "AI_UPSTREAM_PROTOCOL_ERROR",
                     "AI_UPSTREAM_UNAVAILABLE", "AI_UPSTREAM_TIMEOUT":
                    // The server already ended that attempt. Replaying it cannot produce new output.
                    retryID = UUID()
                case "HTTP_502", "HTTP_503", "HTTP_504":
                    retryID = operationID
                default:
                    throw error
                }
            default:
                throw error
            }
            try await Task.sleep(for: .milliseconds(450))
            return try await send(retryID)
        }
    }
}

extension AppEnvironment {
    var sharedGrammarAnalyzer: @Sendable (String, String) async throws -> AIGrammarAnalysis {
        let backend = backendClient, grammar = grammarPoints, llm = llmRouter
        return { sentence, level in
            do {
                return try await SharedGrammarRequest.analyze { operationID in
                    let response: SharedGrammarResponse = try await backend.send(path: "/v1/grammar/analysis", method: "POST",
                        body: GrammarRequestBody(sentence: sentence, learnerLevel: level, operationId: operationID))
                    grammar.mergeSharedPoints(response.learnedPoints)
                    return response.analysis
                }
            } catch BackendClientError.api(_, _, _, let status) where status == 404 {
                // A rollback to the compatible server keeps analysis available.
                return try await GrammarAnalysisService(llm: llm).analyze(sentence: sentence, learnerLevel: level)
            } catch BackendClientError.api(let code, _, _, _) where code == "GRAMMAR_INVALID_OUTPUT" || code == "AI_EMPTY_RESPONSE" {
                throw LLMError.invalidResponse("Invalid grammar model output")
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
