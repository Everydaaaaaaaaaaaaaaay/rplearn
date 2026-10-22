@preconcurrency import AVFoundation
import CoreKit
import Foundation

public enum ListeningSpeechError: Error { case unavailable, playbackFailed }

public struct ListeningSpeechSegment: Sendable, Equatable {
    public let text: String
    public let pauseAfterMs: Int
    public init(text: String, pauseAfterMs: Int = 0) { self.text = text; self.pauseAfterMs = pauseAfterMs }
}

public enum ListeningVoicePolicy {
    public static let maximumPlayCount = 2
    public static func voice(completedPlays: Int) -> SupertonicVoice { completedPlays == 0 ? .f1 : .m5 }

    /// Bound lookahead and memory to one phrase; keep punctuation and word order.
    public static func chunks(_ text: String, limit: Int = 320) -> [String] {
        let sentences = text.replacingOccurrences(of: "(?<=[.!?])\\s+", with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return sentences.flatMap { sentence -> [String] in
            var pieces: [String] = [], current = ""
            for word in sentence.split(whereSeparator: \.isWhitespace) {
                if !current.isEmpty && current.count + word.count + 1 > limit { pieces.append(current); current = "" }
                current += (current.isEmpty ? "" : " ") + word
            }
            if !current.isEmpty { pieces.append(current) }
            return pieces
        }
    }
}

/// One live phrase at a time. No files, persistent PCM cache or Apple fallback.
@MainActor
public final class ListeningSpeechPlayer {
    private let speech: any SpeechService
    private let session: AudioSessionCoordinator
    private var task: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var delegate: Delegate?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var revision = UUID()
    private var bufferID = UUID()

    public init(speech: any SpeechService, session: AudioSessionCoordinator) {
        self.speech = speech; self.session = session
    }

    public func play(segments: [ListeningSpeechSegment], voice: SupertonicVoice, rate: Float = 1,
                     started: @escaping @MainActor @Sendable () -> Void = {},
                     completed: @escaping @MainActor @Sendable (Bool) -> Void) {
        stop()
        let token = revision
        task = Task { [weak self] in
            guard let self else { return }
            var lease: UUID?
            defer { if let lease { Task { await session.releasePlayback(lease) } } }
            do {
                var began = false
                guard !segments.isEmpty else { throw ListeningSpeechError.unavailable }
                for segment in segments {
                    let chunks = ListeningVoicePolicy.chunks(segment.text)
                    guard !chunks.isEmpty else { throw ListeningSpeechError.unavailable }
                    for chunk in chunks {
                        let data = try await speech.synthesizeListening(chunk, voice: voice)
                        try Task.checkCancellation()
                        guard revision == token else { return }
                        if lease == nil { lease = try await session.acquirePlayback() }
                        try Task.checkCancellation()
                        guard revision == token else { return }
                        let audio = try AVAudioPlayer(data: data)
                        audio.enableRate = true; audio.rate = rate
                        let bufferID = UUID(); self.bufferID = bufferID
                        let delegate = Delegate { [weak self] success in
                            guard let self, self.revision == token, self.bufferID == bufferID else { return }
                            self.finishBuffer(success)
                        }
                        self.player = audio; self.delegate = delegate; audio.delegate = delegate
                        audio.prepareToPlay()
                        let success = await withCheckedContinuation { continuation in
                            self.continuation = continuation
                            if audio.play() {
                                if !began { began = true; started() }
                            } else { finishBuffer(false) }
                        }
                        try Task.checkCancellation()
                        guard revision == token else { return }
                        guard success else { throw ListeningSpeechError.playbackFailed }
                    }
                    if segment.pauseAfterMs > 0 {
                        try await Task.sleep(for: .milliseconds(min(30_000, segment.pauseAfterMs)))
                    }
                }
                guard revision == token, !Task.isCancelled else { return }
                completed(true)
            } catch {
                guard revision == token, !Task.isCancelled else { return }
                finishBuffer(false); completed(false)
            }
        }
    }

    public func stop() {
        revision = UUID(); bufferID = UUID(); task?.cancel(); task = nil
        player?.stop(); finishBuffer(false)
    }

    private func finishBuffer(_ success: Bool) {
        player = nil; delegate = nil
        let pending = continuation; continuation = nil; pending?.resume(returning: success)
    }
    private final class Delegate: NSObject, AVAudioPlayerDelegate {
        let finish: @MainActor (Bool) -> Void
        init(_ finish: @escaping @MainActor (Bool) -> Void) { self.finish = finish }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in finish(flag) } }
        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { Task { @MainActor in finish(false) } }
    }
}

enum ListeningPCM {
    static func wave(_ samples: [Float], sampleRate: UInt32) -> Data {
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ number: T) {
            var little = number.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + samples.count * 4)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(3)); append(UInt16(1)); append(sampleRate)
        append(sampleRate * 4); append(UInt16(4)); append(UInt16(32))
        data.append(Data("data".utf8)); append(UInt32(samples.count * 4))
        samples.forEach { append($0.bitPattern) }
        return data
    }
}
