import Foundation
import Testing
import SpeechKit
@testable import ChatFeature

private actor QueuedSpeechProbe: SpeechService {
    var started: [String] = []
    var waiting: CheckedContinuation<Void, Never>?
    var stops = 0
    func speak(_ request: SpeechRequest) async { await speakAndWait(request) }
    func speakAndWait(_ request: SpeechRequest) async {
        started.append(request.text)
        await withCheckedContinuation { waiting = $0 }
    }
    func finish() { let pending = waiting; waiting = nil; pending?.resume() }
    func stopSpeaking() { stops += 1; finish() }
}

@Suite("Chat automatic bubble reading") @MainActor
struct ChatAutoReadQueueTests {
    private func item(_ text: String, id: UUID = UUID()) -> ChatAutoReadQueue.Item {
        .init(id: id, request: SpeechRequest(text: text))
    }
    private func wait(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await predicate())
    }

    @Test("用户和 NPC 气泡按出现顺序等待实际播放完成，快到的消息不打断")
    func fifo() async throws {
        let speech = QueuedSpeechProbe()
        let queue = ChatAutoReadQueue(speech: speech)
        queue.configure(enabled: true, existingIDs: [])
        let user = item("user"), npc1 = item("npc first"), npc2 = item("npc second")
        queue.observe([user])
        try await wait { await speech.started == ["user"] }
        queue.observe([user, npc1, npc2])
        #expect(await speech.started == ["user"])
        #expect(await speech.stops == 0)
        await speech.finish()
        try await wait { await speech.started == ["user", "npc first"] }
        await speech.finish()
        try await wait { await speech.started == ["user", "npc first", "npc second"] }
        await queue.interrupt()?.value
    }

    @Test("不补播历史，重复刷新及翻译不重播，关闭清空等待队列")
    func historyAndDisable() async throws {
        let speech = QueuedSpeechProbe()
        let queue = ChatAutoReadQueue(speech: speech)
        let old = item("old"), first = item("first"), second = item("second")
        queue.configure(enabled: true, existingIDs: [old.id])
        queue.observe([old, first, second])
        try await wait { await speech.started == ["first"] }
        queue.observe([old, first, second])
        queue.configure(enabled: false, existingIDs: [old.id, first.id, second.id])
        await queue.interrupt()?.value
        queue.configure(enabled: true, existingIDs: [old.id, first.id, second.id])
        let fresh = item("fresh")
        queue.observe([old, first, second, fresh])
        try await wait { await speech.started == ["first", "fresh"] }
        await queue.interrupt()?.value
    }

    @Test("快速关闭再开启先停止旧播放，不误停新消息")
    func rapidToggle() async throws {
        let speech = QueuedSpeechProbe()
        let queue = ChatAutoReadQueue(speech: speech)
        queue.configure(enabled: true, existingIDs: [])
        let first = item("first")
        queue.observe([first])
        try await wait { await speech.started == ["first"] }
        queue.configure(enabled: false, existingIDs: [first.id])
        queue.configure(enabled: true, existingIDs: [first.id])
        queue.observe([first, item("new")])
        try await wait { await speech.started == ["first", "new"] }
        #expect(await speech.stops == 1)
        await queue.interrupt()?.value
    }
}
