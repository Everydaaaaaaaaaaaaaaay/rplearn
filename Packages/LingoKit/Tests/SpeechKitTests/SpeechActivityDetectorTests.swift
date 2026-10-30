import AVFoundation
import Foundation
import Testing
@testable import SpeechKit

@Suite("Speech input noise rejection")
struct SpeechActivityDetectorTests {
    private func voice(at sample: Int, rate: Double, amplitude: Double = 0.012) -> Float {
        let time = Double(sample) / rate
        let envelope = 0.7 + 0.3 * sin(2 * .pi * 4 * time)
        return Float(amplitude * envelope * (sin(2 * .pi * 180 * time)
            + 0.5 * sin(2 * .pi * 540 * time) + 0.25 * sin(2 * .pi * 1_260 * time)))
    }

    private func feed(_ samples: [Float], rate: Double = 48_000, chunk: Int = 1_024,
                      to detector: inout SpeechActivityDetector) -> [SpeechActivityDetector.Activity] {
        stride(from: 0, to: samples.count, by: chunk).map { offset in
            Array(samples[offset..<min(offset + chunk, samples.count)]).withUnsafeBufferPointer {
                detector.process(samples: $0, sampleRate: rate)
            }
        }
    }

    @Test("静音、空调低频震动及宽频底噪不建立语音回合", arguments: [8_000.0, 16_000.0, 44_100.0, 48_000.0])
    func ambientNoise(rate: Double) {
        for kind in 0..<3 {
            var detector = SpeechActivityDetector()
            var random: UInt64 = 42
            let samples: [Float] = (0..<Int(rate * 2)).map { i in
                if kind == 0 { return 0 }
                if kind == 1 { return Float(0.08 * sin(2 * .pi * 55 * Double(i) / rate)) }
                random = random &* 6_364_136_223_846_793_005 &+ 1
                return Float(Double(random >> 33) / Double(UInt32.max >> 1) * 2 - 1) * 0.025
            }
            let updates = feed(samples, rate: rate, to: &detector)
            #expect(!detector.hasDetectedSpeech)
            #expect(updates.allSatisfy { !$0.shouldForwardAudio && !$0.didStartSpeech && $0.level == 0 })
        }
    }

    @Test("敲击及反复短促键盘声不会累加成说话")
    func transientNoise() {
        var detector = SpeechActivityDetector()
        let rate = 48_000.0
        let samples = (0..<96_000).map { i -> Float in
            // 20 ms impacts separated by 60 ms; individually much louder than speech.
            i % 3_840 < 960 ? voice(at: i, rate: rate, amplitude: 0.2) : 0
        }
        #expect(feed(samples, to: &detector).allSatisfy { !$0.shouldForwardAudio })
        #expect(!detector.hasDetectedSpeech)
    }

    @Test("短促正常回答保留，不能把简短发声当成敲击声")
    func briefAnswer() {
        var detector = SpeechActivityDetector()
        let samples = (0..<6_720).map { voice(at: $0, rate: 48_000, amplitude: 0.025) }
        _ = feed(samples, to: &detector)
        #expect(detector.hasDetectedSpeech)
    }

    @Test("低音量发声仍可确认，行为不依赖音频块大小", arguments: [256, 1_024, 4_096])
    func quietSpeech(chunk: Int) {
        var detector = SpeechActivityDetector()
        let rate = 48_000.0
        _ = feed(Array(repeating: 0, count: 12_000), to: &detector)
        let samples = (0..<19_200).map { voice(at: $0, rate: rate, amplitude: 0.007) }
        let updates = feed(samples, chunk: chunk, to: &detector)
        #expect(detector.hasDetectedSpeech)
        #expect(updates.contains { $0.didStartSpeech })
        #expect(updates.contains { $0.isSpeech && $0.level > 0 && $0.level < 0.07 })
        let silent = feed(Array(repeating: 0, count: 24_000), to: &detector)
        #expect(silent.last?.shouldForwardAudio == false)
        #expect(silent.last?.level == 0)
        detector.resetTurn()
        #expect(!detector.hasDetectedSpeech)
    }

    @Test("确认前不发送噪音，确认后保留起始音节，缓存不借用复用的音频内存")
    func onsetBufferAndReset() {
        let gate = SpeechAudioGate()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960)!
        buffer.frameLength = 960
        var firstForwarded: Float?
        var forwardedFrames = 0
        func receive() {
            _ = gate.receive(buffer) { accepted in
                if firstForwarded == nil { firstForwarded = accepted.floatChannelData?[0][0] }
                forwardedFrames += Int(accepted.frameLength)
            }
        }
        buffer.floatChannelData?[0].initialize(repeating: 0.00001, count: 960)
        for _ in 0..<20 { receive() }
        #expect(forwardedFrames == 0 && !gate.hasDetectedSpeech)
        for frame in 0..<20 {
            for i in 0..<960 { buffer.floatChannelData?[0][i] = voice(at: frame * 960 + i, rate: 48_000) }
            receive()
        }
        #expect(gate.hasDetectedSpeech && forwardedFrames >= 19_200)
        #expect(firstForwarded == 0.00001)
        gate.resetTurn()
        buffer.floatChannelData?[0].initialize(repeating: 0, count: 960)
        forwardedFrames = 0
        for _ in 0..<20 { receive() }
        #expect(!gate.hasDetectedSpeech && forwardedFrames == 0)
    }
}
