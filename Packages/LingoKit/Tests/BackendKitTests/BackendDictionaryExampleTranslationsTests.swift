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
        private var statuses: [String]

        init(statuses: [String]) { self.statuses = statuses }
        init(status: String) { self.statuses = [status] }

        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            requests.append(request)
            let status = statuses.count > 1 ? statuses.removeFirst() : (statuses.first ?? "missing")
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

    private func request() -> BackendDictionaryExampleTranslationRequest {
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
    }

    private func resolver(
        statuses: [String],
        pollingDelays: [Duration] = []
    ) -> (BackendDictionaryExampleTranslationResolver, MockTransport) {
        let transport = MockTransport(statuses: statuses)
        let backend = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: EmptyCredentialStore(),
            transport: transport
        )
        return (
            BackendDictionaryExampleTranslationResolver(
                backend: backend,
                guestID: "test-device-id",
                pollingDelays: pollingDelays
            ),
            transport
        )
    }

    private func resolver(
        status: String,
        pollingDelays: [Duration] = []
    ) -> (BackendDictionaryExampleTranslationResolver, MockTransport) {
        resolver(statuses: [status], pollingDelays: pollingDelays)
    }

    private func generateOnMissFlags(_ requests: [URLRequest]) throws -> [Bool] {
        try requests.map { request in
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try #require(json["generateOnMiss"] as? Bool)
        }
    }

    @Test("缓存命中只读一次，不触发生成")
    func cacheHitUsesExistingTranslation() async throws {
        let (resolver, transport) = resolver(status: "ready")
        let result = try await resolver.resolve(request())

        #expect(result?.contextualMeaningZhHans == "队友")
        #expect(result?.sentenceZhHans == "这是他第一次以首发身份对阵昔日的队友。")
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(try generateOnMissFlags(requests) == [true])
        #expect(requests.allSatisfy {
            $0.url?.path == "/v1/dictionary/example-translations/resolve"
                && $0.value(forHTTPHeaderField: "x-lingotrip-guest-id") == "test-device-id"
        })
    }

    @Test("未命中时请求生成一次，等不到结果就交给端上翻译")
    func missRequestsGenerationOnce() async throws {
        let (resolver, transport) = resolver(status: "missing")
        let result = try await resolver.resolve(request())

        #expect(result == nil)
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(try generateOnMissFlags(requests) == [true])
    }

    @Test("排队生成后按有界节奏轮询，就绪即返回")
    func pendingPollsUntilReady() async throws {
        let (resolver, transport) = resolver(
            statuses: ["pending", "ready"],
            pollingDelays: [.milliseconds(1)]
        )

        let result = try await resolver.resolve(request())

        #expect(result?.sentenceZhHans == "这是他第一次以首发身份对阵昔日的队友。")
        let requests = await transport.requests
        #expect(requests.count == 2)
        // 首次排队生成，之后只读缓存，不重复排队。
        #expect(try generateOnMissFlags(requests) == [true, false])
    }

    @Test("轮询次数有上限，仍未就绪即放弃")
    func pollingIsBounded() async throws {
        let (resolver, transport) = resolver(
            status: "pending",
            pollingDelays: [.milliseconds(1), .milliseconds(1)]
        )

        let result = try await resolver.resolve(request())

        #expect(result == nil)
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(try generateOnMissFlags(requests) == [true, false, false])
    }
}
