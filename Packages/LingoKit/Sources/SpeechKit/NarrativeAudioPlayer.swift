import AVFoundation
import CoreKit
import Foundation
import Observation

/// A single owner for narrated pages. Stops are serialized before the next request,
/// so an outgoing page cannot cancel a newer line or a dictionary pronunciation.
@MainActor @Observable
public final class NarrativeAudioPlayer {
    public private(set) var completedID: String?
    @ObservationIgnored private let speech: any SpeechService
    @ObservationIgnored private let audioSession: AudioSessionCoordinator
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var stopping: Task<Void, Never>?
    @ObservationIgnored private var rain: AVAudioPlayer?
    @ObservationIgnored private var page: AVAudioPlayer?
    @ObservationIgnored private var sounds: Task<(Data, Data), Never>?
    @ObservationIgnored private let soundEffects: Bool

    public init(speech: any SpeechService, audioSession: AudioSessionCoordinator, soundEffects: Bool = true) {
        self.speech = speech
        self.audioSession = audioSession
        self.soundEffects = soundEffects
    }

    public func play(id: String, request: SpeechRequest?, rainVolume: Float, pageTurn: Bool = true) {
        cancelPlayback(preserveRain: rainVolume > 0)
        if soundEffects && sounds == nil {
            sounds = Task.detached(priority: .utility) {
                (NarrativeSoundBank.rain(), NarrativeSoundBank.page())
            }
        }
        let token = generation
        let barrier = stopping
        playback = Task { [weak self] in
            await barrier?.value
            guard let self, !Task.isCancelled, self.generation == token else { return }
            if let sounds = self.sounds {
                let data = await sounds.value
                guard !Task.isCancelled, self.generation == token else { return }
                if self.rain == nil {
                    self.rain = try? AVAudioPlayer(data: data.0)
                    self.rain?.numberOfLoops = -1
                    self.page = try? AVAudioPlayer(data: data.1)
                    self.page?.volume = 0.08
                }
            }
            try? await self.audioSession.activate(.playback)
            guard !Task.isCancelled, self.generation == token else { return }
            if rainVolume > 0 {
                if self.rain?.isPlaying != true {
                    self.rain?.volume = 0
                    self.rain?.play()
                }
                self.rain?.setVolume(rainVolume, fadeDuration: 0.3)
            }
            if pageTurn { self.page?.currentTime = 0; self.page?.play() }
            if let request {
                // Coalesce extremely quick skips without delaying the visual response.
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard self.generation == token else { return }
                await self.speech.speakAndWait(request)
            }
            guard !Task.isCancelled, self.generation == token else { return }
            self.completedID = id
        }
    }

    public func stop() { cancelPlayback(preserveRain: false) }

    private func cancelPlayback(preserveRain: Bool) {
        generation &+= 1
        completedID = nil
        playback?.cancel()
        playback = nil
        if !preserveRain { rain?.pause() }
        page?.stop()
        let previous = stopping
        let speech = speech
        let audioSession = audioSession
        stopping = Task {
            await previous?.value
            await speech.stopSpeaking()
            if !preserveRain { await audioSession.deactivate() }
        }
    }

    /// Used on teardown/tests when callers need the stop, not merely its dispatch.
    public func waitUntilStopped() async { await stopping?.value }
}

/// Original, deterministic synthesis: quiet filtered rain and a brief paper rustle.
/// No microphone, downloads, copyrighted recordings or per-frame UI processing.
enum NarrativeSoundBank {
    static let sampleRate = 22_050

    static func rain() -> Data { wave(seconds: 24, seed: 955, paper: false) }
    static func page() -> Data { wave(seconds: 0.09, seed: 171, paper: true) }

    private static func wave(seconds: Double, seed: UInt64, paper: Bool) -> Data {
        let count = Int(seconds * Double(sampleRate))
        var state = seed
        var noise = [Double]()
        noise.reserveCapacity(count)
        for _ in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            noise.append(Double(state >> 33) / Double(UInt32.max >> 1) * 2 - 1)
        }
        var low = 0.0
        let coefficient = paper ? 0.06 : 0.12
        // Run one whole period first: the filter enters the delivered period in
        // its circular steady state, not from silence. The wrap is an ordinary
        // adjacent pair of filtered noise samples, with no fade-to-zero or gap.
        if !paper { for value in noise { low += (value - low) * coefficient } }
        var samples = Data(capacity: count * 2)
        for i in 0..<count {
            low += (noise[i] - low) * coefficient
            let t = Double(i) / Double(count)
            let envelope = paper ? pow(sin(.pi * t), 2) : 0.90 + 0.10 * sin(2 * .pi * t)
            var sample = Int16(max(-1, min(1, low * envelope * (paper ? 0.10 : 0.48))) * 32767).littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }
        var result = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { result.append(contentsOf: $0) }
        }
        append(UInt32(36 + samples.count))
        result.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        result.append(Data("data".utf8)); append(UInt32(samples.count))
        result.append(samples)
        return result
    }
}
