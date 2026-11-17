import BackendKit
import Foundation
import Testing
@testable import DomainKit

@Suite("Journey presentation cache") @MainActor
struct JourneyPresentationCacheTests {
    @Test("Concurrent and repeated progress reads share a request")
    func coalescesProgress() async throws {
        let cache = JourneyPresentationCache()
        let service = ProgressService()
        async let first = cache.refreshMainline(using: service)
        async let second = cache.refreshMainline(using: service)
        _ = try await (first, second)
        _ = try await cache.refreshMainline(using: service)
        #expect(await service.calls == 1)
        #expect(cache.mainline != nil)
        #expect(JourneyPresentationCache().mainline == nil)
    }

    @Test("A failed refresh preserves the last successful display snapshot")
    func retainsProgressAfterFailure() async throws {
        let cache = JourneyPresentationCache()
        let service = ProgressService()
        let original = try await cache.refreshMainline(using: service)
        await service.failNext()
        await #expect(throws: CacheTestError.self) {
            try await cache.refreshMainline(using: service, force: true)
        }
        #expect(cache.mainline == original)
        _ = try await cache.refreshMainline(using: service, force: true)
        #expect(await service.calls == 3)
    }

    @Test("Bundled catalogs are bound to both release and city")
    func bundledCatalogIdentity() throws {
        let release = try #require(CityActivityRelease.bundled())
        let cache = JourneyPresentationCache()
        let london = try #require(cache.catalog(releaseID: release.releaseId, cityID: "london"))
        #expect(london.cityId == "london")
        #expect(london.places.allSatisfy { $0.photo.cityId == "london" })
        #expect(cache.catalog(releaseID: "another-release", cityID: "london") == nil)
        #expect(cache.catalog(releaseID: release.releaseId, cityID: "missing-city") == nil)
    }
}

private enum CacheTestError: Error { case unavailable }

private actor ProgressService: MainlineServing {
    private(set) var calls = 0
    private var shouldFail = false
    func failNext() { shouldFail = true }
    func mainlineProgress() async throws -> BackendMainlineProgress {
        calls += 1
        try await Task.sleep(for: .milliseconds(20))
        if shouldFail {
            shouldFail = false
            throw CacheTestError.unavailable
        }
        return try JSONDecoder().decode(BackendMainlineProgress.self, from: Data(#"{"chapters":[]}"#.utf8))
    }
}
