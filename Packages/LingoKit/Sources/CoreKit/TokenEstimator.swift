/// 粗略 token 估算（用于记忆压缩触发与上下文预算，不追求精确）。
/// 经验值：ASCII 约 4 字符/token，CJK 约 1 字符/token。
public enum TokenEstimator {
    public static func estimate(_ text: String) -> Int {
        var asciiCount = 0
        var otherCount = 0
        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                asciiCount += 1
            } else {
                otherCount += 1
            }
        }
        return max(1, asciiCount / 4 + otherCount)
    }
}
