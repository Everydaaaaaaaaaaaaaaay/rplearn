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

    private actor CatalogTransport: BackendTransport {
        var requests: [URLRequest] = []
        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            requests.append(request)
            let json = requests.count == 1 ? #"{"examples":[]}"# : #"{"examples":[{"rank":-199,"partOfSpeech":"art.","definition":"a specific thing","sentence":"Please close the door.","sentenceZhHans":"请关上门。","contextualMeaningZhHans":"特指"}]}"#
            return BackendTransportResponse(data: Data(json.utf8), headers: [:], statusCode: 200)
        }
    }

    @Test("共享例句无需登录，空结果不阻止下次读取新增内容")
    func sharedCatalogRefreshesAfterEmptyResult() async throws {
        let transport = CatalogTransport()
        let backend = BackendClient(configuration: BackendConfiguration(baseURL: URL(string: "https://api.example.com")!),
            credentialStore: EmptyCredentialStore(), transport: transport)
        let resolver = BackendDictionaryExampleTranslationResolver(backend: backend)
        #expect(try await resolver.learnerExamples(for: "the").isEmpty)
        let examples = try await resolver.learnerExamples(for: "the")
        #expect(examples.count == 1)
        #expect(examples.first?.sentenceZhHans == "请关上门。")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.path == "/v1/dictionary/learner-examples/the" && $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == nil })
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
        statuses: [String]
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
                pollingDelays: [.zero, .zero, .zero]
            ),
            transport
        )
    }

    private func resolver(
        status: String
    ) -> (BackendDictionaryExampleTranslationResolver, MockTransport) {
        resolver(statuses: [status])
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
        #expect(try generateOnMissFlags(requests) == [false])
        #expect(requests.allSatisfy {
            $0.url?.path == "/v1/dictionary/example-translations/resolve"
                && $0.value(forHTTPHeaderField: "x-lingotrip-guest-id") == "test-device-id"
        })
    }

    @Test("缺失时最多生成三次，耗尽后交给端上")
    func missRetriesThreeTimes() async throws {
        let (resolver, transport) = resolver(status: "missing")
        let result = try await resolver.resolve(request())

        #expect(result == nil)
        let requests = await transport.requests
        #expect(requests.count == 6)
        #expect(try generateOnMissFlags(requests) == [false, true, false, true, false, true])
    }

    @Test("已有生成任务只轮询，就绪后使用完整译文")
    func pendingPollsWithoutGenerating() async throws {
        let (resolver, transport) = resolver(statuses: ["pending", "ready"])
        #expect(try await resolver.resolve(request())?.sentenceZhHans != nil)
        #expect(try generateOnMissFlags(await transport.requests) == [false, false])
    }

    @Test("第一次生成失败后重新生成成功，成功后停止重试")
    func failedGenerationThenSuccess() async throws {
        let (resolver, transport) = resolver(statuses: ["missing", "pending", "missing", "missing", "pending", "ready"])
        #expect(try await resolver.resolve(request())?.sentenceZhHans != nil)
        #expect(try generateOnMissFlags(await transport.requests) == [false, true, false, false, true, false])
    }

    @Test("生成超时不重复提交付费任务")
    func pendingTimeoutDoesNotRegenerate() async throws {
        let (resolver, transport) = resolver(status: "pending")
        #expect(try await resolver.resolve(request()) == nil)
        #expect(try generateOnMissFlags(await transport.requests) == [false, false, false, false])
    }
}
