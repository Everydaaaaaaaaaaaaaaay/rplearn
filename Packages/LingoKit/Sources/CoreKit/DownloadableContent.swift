import CryptoKit
import Foundation

/// Bundled metadata binds public static files to the exact bytes reviewed for this app version.
public enum DownloadableContent {
    public enum Failure: Error {
        case unavailable
        case invalidFile
    }

    private struct Asset: Decodable, Sendable {
        let file: String
        let bytes: Int
        let bundleName: String
        let sourceSHA256: String?

        var digest: Substring { file.prefix(64) }
        var isValid: Bool {
            let extensions = [".jpg", ".png", ".webp"]
            let suffix = String(file.dropFirst(64))
            return bytes > 0 && bytes <= 16 * 1_024 * 1_024
                && digest.count == 64 && digest.allSatisfy { "0123456789abcdef".contains($0) }
                && extensions.contains(suffix)
                && bundleName.hasSuffix(suffix)
                && !bundleName.contains("/") && !bundleName.contains("..")
        }

        var bundledURL: URL? {
            Bundle.main.url(forResource: bundleName, withExtension: nil)
        }
    }

    private struct Catalog: Decodable, Sendable {
        let assets: [String: Asset]
        let cities: [String: [String]]
        let openings: [String: [String]]
    }

    private static let origin: URL? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LingoTripContentAssetBaseURL") as? String,
              let origin = URL(string: value), let host = origin.host, !host.isEmpty,
              origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil else { return nil }
        if origin.scheme == "https" { return origin }
        #if DEBUG
        if origin.scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return origin }
        #endif
        return nil
    }()

    private static let catalog: Catalog? = {
        guard let manifest = Bundle.main.url(forResource: "downloadable-content", withExtension: "json"),
              let data = try? Data(contentsOf: manifest) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }()

    private static let store = Store()

    public static func contains(_ key: String) -> Bool {
        guard let asset = catalog?.assets[key], asset.isValid else { return false }
        return origin != nil || asset.bundledURL != nil
    }

    public static func file(for key: String, matchingSourceSHA256: String? = nil) async throws -> URL {
        guard let asset = catalog?.assets[key], asset.isValid else {
            throw Failure.unavailable
        }
        if let matchingSourceSHA256, asset.sourceSHA256 != matchingSourceSHA256 {
            throw Failure.invalidFile
        }
        if let bundled = asset.bundledURL {
            return try await store.bundled(bundled, asset: asset)
        }
        guard let origin else { throw Failure.unavailable }
        return try await store.file(asset, origin: origin)
    }

    public static func prefetchCity(_ cityID: String) async {
        guard origin != nil, let keys = catalog?.cities[cityID] else { return }
        await prefetch(keys)
    }

    public static func prefetchOpening(_ readingID: String) async {
        guard origin != nil, let keys = catalog?.openings[readingID] else { return }
        await prefetch(keys)
    }

    public static func prefetch(_ keys: [String]) async {
        for key in keys {
            guard !Task.isCancelled else { return }
            if contains(key) { _ = try? await file(for: key) }
        }
    }

    private actor Store {
        private let directory = URL.cachesDirectory.appending(path: "LingoTrip/DownloadedContent/v1")
        private let limit = 220 * 1_024 * 1_024
        private var verified: Set<String> = []
        private var verifiedBundled: Set<URL> = []
        private var requests: [String: Task<URL, Error>] = [:]
        private static let session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 30
            return URLSession(configuration: configuration)
        }()

        func bundled(_ url: URL, asset: Asset) throws -> URL {
            if verifiedBundled.contains(url) { return url }
            guard try Self.verify(url, matches: asset) else { throw Failure.invalidFile }
            verifiedBundled.insert(url)
            return url
        }

        func file(_ asset: Asset, origin: URL) async throws -> URL {
            let target = directory.appending(path: asset.file)
            if let request = requests[asset.file] { return try await request.value }
            if verified.contains(asset.file), FileManager.default.fileExists(atPath: target.path) {
                touch(target)
                return target
            }

            let request = Task.detached(priority: Task.currentPriority) {
                if (try? Self.verify(target, matches: asset)) == true { return target }
                let (temporary, response) = try await Self.session.download(from: origin.appending(path: asset.file))
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200,
                      try Self.verify(temporary, matches: asset) else { throw Failure.invalidFile }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                let bytes = try Data(contentsOf: temporary, options: .mappedIfSafe)
                try bytes.write(to: target, options: .atomic)
                return target
            }
            requests[asset.file] = request
            defer { requests[asset.file] = nil }
            let url = try await request.value
            verified.insert(asset.file)
            touch(url)
            trim(keeping: asset.file)
            return url
        }

        private static func verify(_ url: URL, matches asset: Asset) throws -> Bool {
            guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == asset.bytes else { return false }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return digest == asset.digest
        }

        private func touch(_ url: URL) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        }

        private func trim(keeping current: String) {
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
            guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return }
            let files = urls.compactMap { url -> (URL, Int, Date)? in
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                      let bytes = values.fileSize else { return nil }
                return (url, bytes, values.contentModificationDate ?? .distantPast)
            }
            var total = files.reduce(0) { $0 + $1.1 }
            guard total > limit else { return }
            for (url, bytes, _) in files.sorted(by: { $0.2 < $1.2 }) where total > limit {
                let name = url.lastPathComponent
                guard name != current, requests[name] == nil,
                      (try? FileManager.default.removeItem(at: url)) != nil else { continue }
                verified.remove(name)
                total -= bytes
            }
        }
    }
}
