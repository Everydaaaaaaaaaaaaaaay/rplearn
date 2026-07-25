/// Server-Sent Events 增量解析器。
///
/// 注意：`URLSession.AsyncBytes.lines` 不产出空行，无法按空行判定事件边界。
/// Anthropic/OpenAI 的 SSE 事件均为单条 `data:` 行（JSON 不含裸换行），
/// 因此这里在收到每条 `data:` 行时立即派发一个事件，`event:` 行只更新当前事件名。
public struct SSEParser: Sendable {
    public struct Event: Sendable, Equatable {
        public var name: String?
        public var data: String

        public init(name: String?, data: String) {
            self.name = name
            self.data = data
        }
    }

    private var currentEventName: String?

    public init() {}

    /// 喂入一行文本；若该行携带 data 则返回一个完整事件。
    public mutating func feed(line: String) -> Event? {
        if line.hasPrefix(":") {
            return nil // SSE 注释（心跳）
        }
        if let value = fieldValue(of: "event", in: line) {
            currentEventName = value
            return nil
        }
        if let value = fieldValue(of: "data", in: line) {
            return Event(name: currentEventName, data: value)
        }
        return nil // 忽略 id:/retry:/未知字段与空行
    }

    private func fieldValue(of field: String, in line: String) -> String? {
        guard line.hasPrefix("\(field):") else { return nil }
        var value = line.dropFirst(field.count + 1)
        if value.hasPrefix(" ") { value = value.dropFirst() }
        return String(value)
    }
}
