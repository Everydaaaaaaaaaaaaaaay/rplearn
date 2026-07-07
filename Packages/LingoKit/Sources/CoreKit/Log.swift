import os

/// 全局日志入口，按模块分类。
public enum Log {
    private static let subsystem = "com.lingotrip.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let llm = Logger(subsystem: subsystem, category: "llm")
    public static let speech = Logger(subsystem: subsystem, category: "speech")
    public static let dict = Logger(subsystem: subsystem, category: "dict")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let story = Logger(subsystem: subsystem, category: "story")
}
