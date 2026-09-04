import Foundation
import Testing
@testable import BackendKit

@Suite("Dictionary example translation backend resolver")
struct BackendDictionaryExampleTranslationsTests {
    private final class EmptyCredentialStore: AuthCredentialStore, @unchecked Sendable {
        func load() throws -> StoredAuthCredential? { nil }
        func remove() throws {}
        func save(_ credential: StoredAuthCredential) throws {}
    }

    private actor MockTransport: BackendTransport {
        private(set) var requests: [URLRequest] = []
        private var responseIndex = 0

        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            requests.append(request)
            let status = responseIndex == 0 ? "pending" : "ready"
            responseIndex += 1
            let output = status == "ready"
                ? #", "sentenceZhHans":"这是他第一次以首发身份对阵昔日的队友。", "contextualMeaningZhHans":"队友""#
                : ""
            let json = """
            {"results":[{"requestId":"mate-request","status":"\(status)","cacheKey":"cache","sourceKey":"source","cache":{"dictionarySource":"ecdict-wordnet","dictionaryVersion":"v1","translationModelVersion":"model","promptVersion":"prompt"}\(output)}]}
            """
            return BackendTransportResponse(
                data: Data(json.utf8),
                headers: [:],
                statusCode: 200
            )
        }
    }

    @Test("miss is queued without blocking the card and a later poll returns both fields")
    func pendingThenReady() async throws {
        let transport = MockTransport()
        let backend = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: EmptyCredentialStore(),
            transport: transport
        )
        let resolver = BackendDictionaryExampleTranslationResolver(
            backend: backend,
            guestID: "test-device-id",
            pollingDelays: [.zero]
        )
        let result = try await resolver.resolve(
            BackendDictionaryExampleTranslationRequest(
                candidateMeaningsZhHans: ["配偶", "对手", "助手", "(象棋)将死"],
                dictionary: BackendDictionaryDescriptor(source: "ecdict-wordnet", version: "v1"),
                lemma: "mate",
                partOfSpeech: "n",
                requestId: "mate-request",
                senseDefinitionEn: "a fellow member of a team",
                sentence: "it was his first start against his former teammates",
                stableSenseId: "n-2-a fellow member of a team"
            )
        )

        #expect(result?.contextualMeaningZhHans == "队友")
        #expect(result?.sentenceZhHans == "这是他第一次以首发身份对阵昔日的队友。")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy {
            $0.url?.path == "/v1/dictionary/example-translations/resolve"
                && $0.value(forHTTPHeaderField: "x-lingotrip-guest-id") == "test-device-id"
        })
        let firstBody = try #require(requests.first?.httpBody)
        let firstJSON = try #require(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        #expect(firstJSON["generateOnMiss"] as? Bool == true)
        let secondBody = try #require(requests.last?.httpBody)
        let secondJSON = try #require(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        #expect(secondJSON["generateOnMiss"] as? Bool == false)
    }
}
