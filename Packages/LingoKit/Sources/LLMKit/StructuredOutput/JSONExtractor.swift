import Foundation

/// 从模型文本输出中提取 JSON 的兜底链：直接解析 → 剥代码围栏 → 截取首个 { 到最后一个 }。
/// 再往后的「fast 档重问修复」由调用方（DomainKit 服务）负责。
public enum JSONExtractor {
    public static func extractJSONData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = validJSONData(trimmed) {
            return data
        }
        if let unfenced = stripCodeFence(from: trimmed), let data = validJSONData(unfenced) {
            return data
        }
        if let sliced = sliceBraces(from: trimmed), let data = validJSONData(sliced) {
            return data
        }
        return nil
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let data = extractJSONData(from: text) else {
            throw LLMError.invalidResponse("输出中未找到合法 JSON")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func validJSONData(_ text: String) -> Data? {
        let data = Data(text.utf8)
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
        return data
    }

    private static func stripCodeFence(from text: String) -> String? {
        guard text.hasPrefix("```") else { return nil }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else { return nil }
        lines.removeFirst() // ``` 或 ```json
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sliceBraces(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(text[start...end])
    }
}
