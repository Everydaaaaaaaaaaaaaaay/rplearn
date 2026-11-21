import Foundation
import Testing
@testable import CoreKit

@Suite("Bounded asynchronous waits")
struct AsyncDeadlineTests {
    private actor Gate {
        var released = false
        var continuation: CheckedContinuation<String, Never>?
        func wait() async -> String {
            if released { return "late" }
            return await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(returning: "late"); continuation = nil }
    }

    @Test("不响应取消的回调也不能阻止超时返回，迟到的完成只丢弃一次")
    func nonCooperativeTimeout() async {
        let gate = Gate(), start = ContinuousClock.now
        do {
            _ = try await AsyncDeadline.run(timeout: .milliseconds(30)) { await gate.wait() }
            Issue.record("Expected timeout")
        } catch { #expect((error as? URLError)?.code == .timedOut) }
        #expect(start.duration(to: .now) < .seconds(1))
        await gate.release()
    }

    @Test("调用方取消会立即结束等待，无需等底层回调")
    func cancellation() async {
        let gate = Gate()
        let task = Task { try await AsyncDeadline.run(timeout: .seconds(10)) { await gate.wait() } }
        await Task.yield()
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        await gate.release()
    }

    @Test("成功值和原始错误正常传递")
    func successAndError() async throws {
        #expect(try await AsyncDeadline.run(timeout: .seconds(1)) { 42 } == 42)
        enum Failure: Error { case expected }
        await #expect(throws: Failure.expected) {
            try await AsyncDeadline.run(timeout: .seconds(1)) { throw Failure.expected } as Int
        }
    }
}
