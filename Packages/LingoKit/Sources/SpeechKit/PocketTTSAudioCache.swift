import CryptoKit
import Foundation

struct PocketTTSAudioCacheKey: Hashable, Sendable {
    private static let pipelineVersion = "pocket-tts-v2.1-int8-gpu-24khz-t065-cache-v1"

    let text: String
    let language: String
    let voiceID: String

    init(text: String, language: String, voiceID: String) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language.lowercased()
        self.voiceID = voiceID
    }

    var fileName: String {
        let source = [Self.pipelineVersion, language, voiceID, text].joined(separator: "\u{0}")
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".f32"
    }
}

enum PocketTTSAudioCachePolicy {
    static let maximumTextBytes = 128

    static func shouldCache(text: String, purpose: SpeechPurpose) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return purpose == .pronunciation
            && !trimmed.isEmpty
            && trimmed.utf8.count <= maximumTextBytes
    }
}

/// 单词发音缓存。内存层负责同一会话的即时重播，磁盘层让下次启动也无需重新推理。
/// 文件位于系统 Caches 目录，可由 iOS 在空间不足时安全清理。
actor PocketTTSAudioCache {
    private struct MemoryEntry {
        let samples: [Float]
        let byteCount: Int
        var lastAccess: UInt64
    }

    private static let header = Data([0x50, 0x54, 0x54, 0x53, 0x01, 0x00, 0x00, 0x00])

    private let directory: URL
    private let fileManager = FileManager.default
    private let memoryLimitBytes: Int
    private let diskLimitBytes: Int
    private let maximumItemBytes: Int

    private var memoryEntries: [PocketTTSAudioCacheKey: MemoryEntry] = [:]
    private var memoryBytes = 0
    private var accessCounter: UInt64 = 0

    init(
        directory: URL,
        memoryLimitBytes: Int = 16 * 1_024 * 1_024,
        diskLimitBytes: Int = 64 * 1_024 * 1_024,
        maximumItemBytes: Int = 8 * 1_024 * 1_024
    ) {
        self.directory = directory
        self.memoryLimitBytes = max(0, memoryLimitBytes)
        self.diskLimitBytes = max(0, diskLimitBytes)
        self.maximumItemBytes = max(0, maximumItemBytes)
    }

    func samples(for key: PocketTTSAudioCacheKey) -> [Float]? {
        accessCounter &+= 1
        if var entry = memoryEntries[key] {
            entry.lastAccess = accessCounter
            memoryEntries[key] = entry
            return entry.samples
        }

        let fileURL = directory.appendingPathComponent(key.fileName)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              data.count <= maximumItemBytes + Self.header.count,
              let samples = Self.decode(data)
        else { return nil }

        insertIntoMemory(samples, for: key)
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
        return samples
    }

    func insert(_ samples: [Float], for key: PocketTTSAudioCacheKey) {
        let byteCount = samples.count * MemoryLayout<Float>.stride
        guard !samples.isEmpty, byteCount <= maximumItemBytes else { return }

        insertIntoMemory(samples, for: key)
        guard diskLimitBytes > 0 else { return }

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try Self.encode(samples).write(
                to: directory.appendingPathComponent(key.fileName),
                options: .atomic
            )
            trimDiskIfNeeded()
        } catch {
            // 缓存失败不能影响真实播放；下次点击只会重新合成。
        }
    }

    private func insertIntoMemory(_ samples: [Float], for key: PocketTTSAudioCacheKey) {
        guard memoryLimitBytes > 0 else { return }
        accessCounter &+= 1
        if let existing = memoryEntries[key] {
            memoryBytes -= existing.byteCount
        }
        let byteCount = samples.count * MemoryLayout<Float>.stride
        memoryEntries[key] = MemoryEntry(
            samples: samples,
            byteCount: byteCount,
            lastAccess: accessCounter
        )
        memoryBytes += byteCount

        while memoryBytes > memoryLimitBytes,
              let oldestKey = memoryEntries.min(by: {
                  $0.value.lastAccess < $1.value.lastAccess
              })?.key,
              let removed = memoryEntries.removeValue(forKey: oldestKey) {
            memoryBytes -= removed.byteCount
        }
    }

    private func trimDiskIfNeeded() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let files = urls.compactMap { url -> (url: URL, date: Date, bytes: Int)? in
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ), let bytes = values.fileSize else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, bytes)
        }
        var totalBytes = files.reduce(0) { $0 + $1.bytes }
        for file in files.sorted(by: { $0.date < $1.date }) where totalBytes > diskLimitBytes {
            guard (try? fileManager.removeItem(at: file.url)) != nil else { continue }
            totalBytes -= file.bytes
        }
    }

    private static func encode(_ samples: [Float]) -> Data {
        var data = header
        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            data.append(
                contentsOf: UnsafeRawBufferPointer(
                    start: baseAddress,
                    count: buffer.count * MemoryLayout<Float>.stride
                )
            )
        }
        return data
    }

    private static func decode(_ data: Data) -> [Float]? {
        guard data.starts(with: header) else { return nil }
        let payload = data.dropFirst(header.count)
        guard !payload.isEmpty, payload.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            return nil
        }

        var samples = [Float](
            repeating: 0,
            count: payload.count / MemoryLayout<Float>.stride
        )
        _ = samples.withUnsafeMutableBufferPointer { buffer in
            payload.copyBytes(to: UnsafeMutableRawBufferPointer(buffer))
        }
        return samples
    }
}
