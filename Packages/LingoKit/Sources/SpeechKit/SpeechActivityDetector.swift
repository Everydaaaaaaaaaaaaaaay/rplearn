import Foundation

/// A small acoustic gate before Apple Speech, independent of tap size and sample rate.
/// System voice processing handles denoising; this gate rejects low-SNR backgrounds,
/// low-frequency rumble and brief impacts without treating the waveform meter as VAD.
public struct SpeechActivityDetector: Sendable {
    public enum Mode: Sendable { case dictation, conversation }
    public struct Activity: Sendable {
        public let level: Double
        public let isSpeech: Bool
        public let didStartSpeech: Bool
        public let shouldForwardAudio: Bool
    }

    public private(set) var hasDetectedSpeech = false
    private var sampleRate = 0.0
    private var highPassCoefficient = 0.0
    private var lowPassCoefficient = 0.0
    private var previousInput = 0.0
    private var highPass = 0.0
    private var bandPass = 0.0
    private var frameSamples = 0
    private var rawEnergy = 0.0
    private var bandEnergy = 0.0
    private var crossings = 0
    private var previousSign = false
    private var noiseRMS = 0.0005
    private var candidateDuration = 0.0
    private var candidateGap = 0.0
    private var candidateWindow = 0.0
    private var releaseRemaining = 0.0
    private var gateOpen = false
    private var frameIsSpeech = false
    private var speechLevel = 0.0
    private let mode: Mode
    private var recentEnergy: [Double] = []
    private var energyIndex = 0

    public init(mode: Mode = .dictation) { self.mode = mode }

    /// Preserve the measured background between recognition turns, never speech evidence.
    public mutating func resetTurn() {
        hasDetectedSpeech = false
        candidateDuration = 0
        candidateGap = 0
        candidateWindow = 0
        releaseRemaining = 0
        gateOpen = false
        frameIsSpeech = false
        speechLevel = 0
        resetFrame()
    }

    public mutating func process(samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> Activity {
        guard sampleRate.isFinite, sampleRate >= 8_000, !samples.isEmpty else {
            return Activity(level: 0, isSpeech: false, didStartSpeech: false, shouldForwardAudio: false)
        }
        if self.sampleRate != sampleRate {
            self = Self(mode: mode)
            self.sampleRate = sampleRate
            highPassCoefficient = exp(-2 * .pi * 120 / sampleRate)
            lowPassCoefficient = 1 - exp(-2 * .pi * 3_800 / sampleRate)
        }
        var didStart = false
        var forwarded = gateOpen
        let frameLength = max(1, Int(sampleRate * 0.02))
        for sample in samples {
            let value = sample.isFinite ? Double(sample) : 0
            highPass = highPassCoefficient * (highPass + value - previousInput)
            previousInput = value
            bandPass += lowPassCoefficient * (highPass - bandPass)
            rawEnergy += value * value
            bandEnergy += bandPass * bandPass
            let sign = value >= 0
            if frameSamples > 0, sign != previousSign { crossings += 1 }
            previousSign = sign
            frameSamples += 1
            if frameSamples >= frameLength {
                let wasOpen = gateOpen
                evaluateFrame(duration: Double(frameSamples) / sampleRate)
                didStart = didStart || (!wasOpen && gateOpen)
                forwarded = forwarded || gateOpen
                resetFrame()
            }
        }
        return Activity(level: frameIsSpeech ? speechLevel : 0, isSpeech: frameIsSpeech,
                        didStartSpeech: didStart, shouldForwardAudio: forwarded)
    }

    private mutating func evaluateFrame(duration: Double) {
        let rms = sqrt(bandEnergy / Double(frameSamples))
        if mode == .conversation { adaptStationaryBackground(rms) }
        let bandRatio = bandEnergy / max(rawEnergy, 1e-12)
        let crossingRate = Double(crossings) / duration
        // Broadband hiss and sub-bass vibration should not establish a speech turn.
        let voiceBand = bandRatio >= 0.42 && crossingRate >= 70 && crossingRate <= min(4_500, sampleRate * 0.28)
        let threshold = max(gateOpen ? 0.0014 : 0.002, noiseRMS * (gateOpen ? 1.8 : 2.8))
        let candidate = voiceBand && rms >= threshold
        if candidateDuration > 0 || candidate { candidateWindow += duration }
        if candidate {
            candidateDuration += duration
            candidateGap = 0
            if candidateDuration >= 0.12 { gateOpen = true; hasDetectedSpeech = true }
            if gateOpen { releaseRemaining = 0.28 }
        } else {
            candidateGap += duration
            if candidateGap > 0.04 { candidateDuration = 0; candidateWindow = 0 }
            releaseRemaining = max(0, releaseRemaining - duration)
            if releaseRemaining == 0 { gateOpen = false }
            if !gateOpen {
                let timeConstant = rms < noiseRMS ? 0.12 : 0.7
                let blend = 1 - exp(-duration / timeConstant)
                noiseRMS += (min(rms, 0.02) - noiseRMS) * blend
            }
        }
        if !gateOpen, candidateWindow > 0.22 { candidateDuration = 0; candidateWindow = 0 }
        frameIsSpeech = gateOpen && candidate
        speechLevel = min(1, rms * 6)
    }

    private mutating func adaptStationaryBackground(_ rms: Double) {
        // A fixed background can pass the initial energy gate. Learn it even
        // while the gate is open, otherwise it can keep a call turn alive forever.
        // Speech-like amplitude modulation must not be absorbed into this floor.
        let window = 50 // one second of 20 ms frames, independent of tap size
        if recentEnergy.count < window { recentEnergy.append(rms) }
        else { recentEnergy[energyIndex] = rms }
        energyIndex = (energyIndex + 1) % window
        guard recentEnergy.count == window else { return }
        let mean = recentEnergy.reduce(0, +) / Double(window)
        guard mean > 0.0001 else { return }
        let variance = recentEnergy.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window)
        if sqrt(variance) / mean < 0.10 { noiseRMS = max(noiseRMS, mean) }
    }

    private mutating func resetFrame() {
        frameSamples = 0
        rawEnergy = 0
        bandEnergy = 0
        crossings = 0
    }
}
