import Foundation

/// 音量计算（纯函数，供录音波形动画）。
public enum AudioLevelMeter {
    /// RMS → 0...1 的显示级别。
    public static func level(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.withUnsafeBufferPointer { buffer in
            level(samples: buffer)
        }
    }

    /// RMS → 0...1 的显示级别；供音频 tap 直接从 buffer 计算，避免实时线程分配数组。
    public static func level(samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        // 人声 RMS 通常在 0.01~0.3，放大并截断到 0...1
        return min(1, max(0, Double(rms) * 6))
    }
}
