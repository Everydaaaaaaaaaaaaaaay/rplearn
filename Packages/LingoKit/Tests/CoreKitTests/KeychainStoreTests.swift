import CoreKit
import Foundation
import Testing

@Suite("KeychainStore")
struct KeychainStoreTests {
    private let store = KeychainStore(service: "com.lingotrip.tests")

    @Test("写入、读取、更新、删除全流程")
    func roundTrip() throws {
        let key = "smoke-\(UUID().uuidString)"

        #expect(try store.string(for: key) == nil)

        try store.setString("hello", for: key)
        #expect(try store.string(for: key) == "hello")

        try store.setString("world", for: key)
        #expect(try store.string(for: key) == "world")

        try store.removeValue(for: key)
        #expect(try store.string(for: key) == nil)
    }

    @Test("删除不存在的 key 不抛错")
    func removeAbsentKey() throws {
        try store.removeValue(for: "never-existed-\(UUID().uuidString)")
    }
}

@Suite("Account local preferences")
struct AccountLocalPreferenceTests {
    @Test("主动消息设置和未读缓存按账号隔离")
    func preferencesAreAccountScoped() throws {
        let suite = "AccountLocalPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456711")!
        let second = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456712")!

        #expect(ProactiveMessagePreferences.isEnabled(for: first, defaults: defaults))
        #expect(ProactiveMessagePreferences.isEnabled(for: second, defaults: defaults))
        ProactiveMessagePreferences.setEnabled(false, for: first, defaults: defaults)

        #expect(!ProactiveMessagePreferences.isEnabled(for: first, defaults: defaults))
        #expect(ProactiveMessagePreferences.isEnabled(for: second, defaults: defaults))
        #expect(
            ProactiveMessagePreferences.unreadCountKey(for: first)
                != ProactiveMessagePreferences.unreadCountKey(for: second)
        )
    }
}
