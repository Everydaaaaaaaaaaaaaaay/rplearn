import AVFoundation
import CoreKit
import Foundation
import Testing
@testable import SpeechKit

@Suite("语音消息原音回放", .serialized) @MainActor
struct VoiceMessagePlayerTests {
    @Test("文件引用变化后按消息身份播放，结束后可重听，同条再次点击停止")
    func replayAndStop() async throws {
        let file = try recording()
        defer { VoiceMessageStorage.delete(fileName: file) }
        let player = VoiceMessagePlayer(audioSession: AudioSessionCoordinator())
        let id = UUID()
        await player.togglePlay(messageID: id) { file }
        #expect(player.playingMessageID == id)
        #expect(player.playingFileName == file)
        #expect(await eventually { player.playingMessageID == nil })
        await player.togglePlay(messageID: id) { file }
        #expect(player.playingMessageID == id)
        await player.togglePlay(messageID: id) { Issue.record("停止时不应重新下载"); return nil }
        #expect(player.playingMessageID == nil)
    }

    @Test("取消下载及切换语音后，旧下载结果不会启动播放")
    func staleDownloadCannotPlay() async throws {
        let file = try recording()
        defer { VoiceMessageStorage.delete(fileName: file) }
        let player = VoiceMessagePlayer(audioSession: AudioSessionCoordinator())
        let old = UUID()
        var continuation: CheckedContinuation<String?, Never>?
        let task = Task {
            await player.togglePlay(messageID: old) {
                await withCheckedContinuation { continuation = $0 }
            }
        }
        #expect(await eventually { continuation != nil })
        #expect(player.loadingMessageID == old)
        let next = UUID()
        await player.togglePlay(messageID: next) { file }
        continuation?.resume(returning: file)
        await task.value
        #expect(player.playingMessageID == next)
        player.stop()
        #expect(player.loadingMessageID == nil)
    }

    @Test("下载或解码失败可点击原条重试")
    func failureCanRetry() async throws {
        let file = try recording()
        defer { VoiceMessageStorage.delete(fileName: file) }
        let player = VoiceMessagePlayer(audioSession: AudioSessionCoordinator())
        let id = UUID()
        await player.togglePlay(messageID: id) { nil }
        #expect(player.failedMessageID == id)
        #expect(player.loadingMessageID == nil)
        await player.togglePlay(messageID: id) { VoiceMessageStorage.newFileName() }
        #expect(player.failedMessageID == id)
        await player.togglePlay(messageID: id) { file }
        #expect(player.failedMessageID == nil)
        #expect(player.playingMessageID == id)
        player.stop()
    }

    @Test("取消下载任务后不残留加载状态或恢复播放")
    func cancelledLoadingClearsState() async {
        let player = VoiceMessagePlayer(audioSession: AudioSessionCoordinator())
        var continuation: CheckedContinuation<String?, Never>?
        let task = Task {
            await player.togglePlay(messageID: UUID()) {
                await withCheckedContinuation { continuation = $0 }
            }
        }
        #expect(await eventually { continuation != nil })
        task.cancel()
        continuation?.resume(returning: VoiceMessageStorage.newFileName())
        await task.value
        #expect(player.loadingMessageID == nil)
        #expect(player.playingMessageID == nil)
        #expect(player.failedMessageID == nil)
    }

    private func recording() throws -> String {
        let name = VoiceMessageStorage.newFileName()
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 9_600)!
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * 220 / 16_000) * 0.05)
        }
        let file = try AVAudioFile(forWriting: VoiceMessageStorage.url(for: name), settings: format.settings)
        try file.write(from: buffer)
        return name
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<150 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}
