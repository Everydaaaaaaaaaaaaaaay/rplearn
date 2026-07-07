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
