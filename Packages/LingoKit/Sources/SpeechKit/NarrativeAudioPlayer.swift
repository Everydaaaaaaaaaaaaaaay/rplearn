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
    @ObservationIgnored private var preparedPlayer: AVAudioPlayer?
    @ObservationIgnored private var preparedIdentity: (id: String, url: URL)?
    @ObservationIgnored private var pausedCompletedID: String?
    @ObservationIgnored private var resumePoint: (id: String, url: URL, time: Double)?
    @ObservationIgnored private var rain: AVAudioPlayer?
    @ObservationIgnored private var page: AVAudioPlayer?
    @ObservationIgnored private var sounds: Task<(Data, Data), Never>?
    @ObservationIgnored private let soundEffects: Bool

    public init(speech: any SpeechService, audioSession: AudioSessionCoordinator, soundEffects: Bool = true) {
        self.speech = speech
        self.audioSession = audioSession
        self.soundEffects = soundEffects
    }

    public func play(id: String, request: SpeechRequest?, rainVolume: Float, pageTurn: Bool = true, prepared: PreparedNarration? = nil) {
        let alreadyCompleted = pausedCompletedID == id && prepared != nil
        if request?.purpose != .pronunciation { pausedCompletedID = nil }
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
            var playedPrepared = false
            if let prepared, !alreadyCompleted {
                do {
                    let player = try AVAudioPlayer(contentsOf: prepared.url)
                    self.preparedPlayer = player
                    self.preparedIdentity = (id, prepared.url)
                    if let resume = self.resumePoint, resume.id == id, resume.url == prepared.url {
                        player.currentTime = min(resume.time, max(0, player.duration - 0.02))
                    }
                    self.resumePoint = nil
                    player.prepareToPlay()
                    playedPrepared = player.play()
                    if playedPrepared {
                        NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: nil)
                        // Track real playback completion, including the authored
                        // final beat. Cancellation never publishes a completion.
                        while player.isPlaying {
                            try await Task.sleep(for: .milliseconds(20))
                            guard self.generation == token else { return }
                        }
                    }
                } catch is CancellationError { return } catch {
                    // Decode/device failures use the existing plain-text renderer.
                    self.preparedPlayer?.stop()
                }
            } else if request?.purpose != .pronunciation { self.resumePoint = nil }
            if !alreadyCompleted, !playedPrepared, let request {
                // Coalesce extremely quick skips without delaying the visual response.
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard self.generation == token else { return }
                await self.speech.speakAndWait(request)
            }
            guard !Task.isCancelled, self.generation == token else { return }
            self.preparedPlayer = nil
            self.preparedIdentity = nil
            self.completedID = id
        }
    }

    public func stop() {
        resumePoint = nil
        pausedCompletedID = nil
        cancelPlayback(preserveRain: false)
    }

    /// Dictionary/history/background overlays pause a prepared line. Returning
    /// resumes its real sample position instead of silently skipping its tail.
    public func pause() {
        if let completedID, completedID != "lookup" { pausedCompletedID = completedID }
        if let player = preparedPlayer, let identity = preparedIdentity {
            resumePoint = (identity.id, identity.url, player.currentTime)
        }
        cancelPlayback(preserveRain: false)
    }

    private func cancelPlayback(preserveRain: Bool) {
        generation &+= 1
        completedID = nil
        playback?.cancel()
        playback = nil
        if !preserveRain { rain?.pause() }
        page?.stop()
        preparedPlayer?.stop()
        preparedPlayer = nil
        preparedIdentity = nil
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

    static func rain() -> Data { wave(seconds: 48, seed: 955, paper: false) }
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
            // Stationary rain: no audible periodic swell or reset in loudness.
            // The same circular filter produces its timbre on both sides of the
            // join; fading unrelated ends together would change noise energy.
            let envelope = paper ? pow(sin(.pi * t), 2) : 0.90
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
