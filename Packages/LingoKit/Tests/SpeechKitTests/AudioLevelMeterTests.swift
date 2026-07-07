import Testing
@testable import SpeechKit

@Suite("AudioLevelMeter")
struct AudioLevelMeterTests {
    @Test("静音为 0，满幅接近 1，普通人声居中")
    func levels() {
        #expect(AudioLevelMeter.level(samples: []) == 0)
        #expect(AudioLevelMeter.level(samples: [0, 0, 0, 0]) == 0)
        let loud = AudioLevelMeter.level(samples: Array(repeating: 0.9, count: 512))
        #expect(loud == 1)
        let speech = AudioLevelMeter.level(samples: Array(repeating: 0.05, count: 512))
        #expect(speech > 0.1 && speech < 0.6)
    }

    @Test("正负对称信号与其绝对值等级相同")
    func symmetry() {
        let positive = AudioLevelMeter.level(samples: [0.1, 0.1, 0.1, 0.1])
        let mixed = AudioLevelMeter.level(samples: [0.1, -0.1, 0.1, -0.1])
        #expect(abs(positive - mixed) < 0.0001)
    }
}
