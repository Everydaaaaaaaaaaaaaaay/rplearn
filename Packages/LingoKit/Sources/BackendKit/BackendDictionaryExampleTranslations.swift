import Foundation

public struct BackendDictionaryDescriptor: Codable, Sendable, Equatable {
    public let source: String
    public let version: String

    public init(source: String, version: String) {
        self.source = source
        self.version = version
    }
}

public struct BackendDictionaryExampleTranslationRequest: Codable, Sendable, Equatable {
    public let candidateMeaningsZhHans: [String]
    public let dictionary: BackendDictionaryDescriptor
    public let lemma: String
    public let partOfSpeech: String
    public let requestId: String
    public let senseDefinitionEn: String?
    public let sentence: String
    public let stableSenseId: String?

    public init(
        candidateMeaningsZhHans: [String],
        dictionary: BackendDictionaryDescriptor,
        lemma: String,
        partOfSpeech: String,
        requestId: String = UUID().uuidString.lowercased(),
        senseDefinitionEn: String? = nil,
        sentence: String,
        stableSenseId: String? = nil
    ) {
        self.candidateMeaningsZhHans = candidateMeaningsZhHans
        self.dictionary = dictionary
        self.lemma = lemma
        self.partOfSpeech = partOfSpeech
        self.requestId = requestId
        self.senseDefinitionEn = senseDefinitionEn
        self.sentence = sentence
        self.stableSenseId = stableSenseId
    }
}

public struct BackendDictionaryExampleTranslation: Sendable, Equatable {
    public let contextualMeaningZhHans: String
    public let sentenceZhHans: String

    public init(contextualMeaningZhHans: String, sentenceZhHans: String) {
        self.contextualMeaningZhHans = contextualMeaningZhHans
        self.sentenceZhHans = sentenceZhHans
    }
}

/// Resolves dictionary example translations through the server cache and, on a miss,
/// asks the server to generate one with the dictionary AI route. Bounded polling keeps
/// the card's translation row up to date while it remains visible; a timeout or a
/// failed request returns nil so the caller can fall back to on-device translation.
public struct BackendDictionaryExampleTranslationResolver: Sendable {
    private struct ResolveBody: Encodable, Sendable {
        let generateOnMiss: Bool
        let requests: [BackendDictionaryExampleTranslationRequest]
    }

    private struct ResolveResponse: Decodable, Sendable {
        let results: [ResolveResult]
    }

    private struct ResolveResult: Decodable, Sendable {
        let contextualMeaningZhHans: String?
        let requestId: String?
        let sentenceZhHans: String?
        let status: Status

        enum Status: String, Decodable, Sendable {
            case missing
            case pending
            case ready
        }
    }

    private let backend: BackendClient
    private let guestID: String?
    private let pollingDelays: [Duration]
    private let retryDelay: Duration

    public init(backend: BackendClient, guestID: String? = nil) {
        self.init(backend: backend, guestID: guestID,
                  pollingDelays: [.milliseconds(500), .seconds(1)] + Array(repeating: .seconds(2), count: 45),
                  retryDelay: .milliseconds(500))
    }

    init(backend: BackendClient, guestID: String?, pollingDelays: [Duration], retryDelay: Duration = .zero) {
        self.backend = backend
        self.guestID = guestID
        self.pollingDelays = pollingDelays
        self.retryDelay = retryDelay
    }

    /// Cache first, then at most three generation attempts. Pending jobs are only
    /// polled; never enqueue another paid generation while one is still running.
    public func resolve(
        _ request: BackendDictionaryExampleTranslationRequest
    ) async throws -> BackendDictionaryExampleTranslation? {
        var lastError: Error?
        for attempt in 0..<3 {
            try Task.checkCancellation()
            if attempt > 0 { try await Task.sleep(for: retryDelay) }
            do {
                var result = try await send(request, generateOnMiss: false)
                if let ready = readyTranslation(from: result) { return ready }
                if result.status != .pending {
                    result = try await send(request, generateOnMiss: true)
                    if let ready = readyTranslation(from: result) { return ready }
                }
                for delay in pollingDelays {
                    guard result.status == .pending else { break }
                    try await Task.sleep(for: delay)
                    try Task.checkCancellation()
                    result = try await send(request, generateOnMiss: false)
                    if let ready = readyTranslation(from: result) { return ready }
                }
                // A worker that remains unavailable must not hold the UI forever.
                // Its eventual result will still be persisted for the next lookup.
                if result.status == .pending { return nil }
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    private func send(
        _ request: BackendDictionaryExampleTranslationRequest,
        generateOnMiss: Bool
    ) async throws -> ResolveResult {
        let body = ResolveBody(
            generateOnMiss: generateOnMiss,
            requests: [request]
        )
        let response: ResolveResponse
        if let guestID {
            response = try await backend.sendWithGuestAccess(
                path: "/v1/dictionary/example-translations/resolve",
                method: "POST",
                body: body,
                guestID: guestID
            )
        } else {
            response = try await backend.send(
                path: "/v1/dictionary/example-translations/resolve",
                method: "POST",
                body: body
            )
        }
        guard let result = response.results.first,
              response.results.count == 1,
              result.requestId == request.requestId
        else {
            throw BackendClientError.invalidResponse
        }
        return result
    }

    private func readyTranslation(
        from result: ResolveResult
    ) -> BackendDictionaryExampleTranslation? {
        guard result.status == .ready,
              let sentence = result.sentenceZhHans?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              let meaning = result.contextualMeaningZhHans?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !sentence.isEmpty,
              !meaning.isEmpty
        else { return nil }
        return BackendDictionaryExampleTranslation(
            contextualMeaningZhHans: meaning,
            sentenceZhHans: sentence
        )
    }
}
