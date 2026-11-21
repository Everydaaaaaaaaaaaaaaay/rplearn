@preconcurrency import AVFoundation
import Foundation

/// Keeps a short onset buffer so sustained-speech confirmation does not clip a word.
/// Its lock also serializes the audio tap and recognition-turn replacement.
public final class SpeechAudioGate: @unchecked Sendable {
    private let lock = NSLock()
    private var detector: SpeechActivityDetector
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollDuration = 0.0

    public init(mode: SpeechActivityDetector.Mode = .dictation) {
        detector = SpeechActivityDetector(mode: mode)
    }

    public var hasDetectedSpeech: Bool { lock.withLock { detector.hasDetectedSpeech } }

    public func resetTurn() {
        lock.withLock {
            detector.resetTurn()
            preRoll.removeAll(keepingCapacity: true)
            preRollDuration = 0
        }
    }

    public func receive(_ buffer: AVAudioPCMBuffer, append: (AVAudioPCMBuffer) -> Void) -> SpeechActivityDetector.Activity {
        lock.withLock {
            guard let channel = buffer.floatChannelData?[0] else {
                return detector.process(samples: UnsafeBufferPointer<Float>(start: nil, count: 0), sampleRate: 0)
            }
            let activity = detector.process(
                samples: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)),
                sampleRate: buffer.format.sampleRate)
            if activity.shouldForwardAudio {
                for onset in preRoll { append(onset) }
                preRoll.removeAll(keepingCapacity: true)
                preRollDuration = 0
                append(buffer)
            } else if let copy = Self.copy(buffer) {
                preRoll.append(copy)
                preRollDuration += Double(copy.frameLength) / copy.format.sampleRate
                while preRollDuration > 0.28, preRoll.count > 1 {
                    let removed = preRoll.removeFirst()
                    preRollDuration -= Double(removed.frameLength) / removed.format.sampleRate
                }
            }
            return activity
        }
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        copy.frameLength = source.frameLength
        let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let output = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(input, output) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(from.mDataByteSize))
        }
        return copy
    }
}
