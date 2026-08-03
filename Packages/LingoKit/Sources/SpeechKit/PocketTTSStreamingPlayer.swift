@preconcurrency import AVFoundation
import Foundation

enum PocketTTSPlaybackError: LocalizedError {
    case audioFormatUnavailable
    case audioBufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .audioFormatUnavailable:
            "无法建立 Pocket TTS 音频格式。"
        case .audioBufferAllocationFailed:
            "无法分配 Pocket TTS 播放缓冲区。"
        }
    }
}

/// 主线程隔离的流式 PCM 播放器。模型每产出一帧就立刻排入播放器，
/// 不等待整句合成完成，因此首帧延迟不会被句子长度放大。
@MainActor
final class PocketTTSStreamingPlayer {
    private static let prebufferFrameCount = 2

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat

    private var generation: UInt64 = 0
    private var scheduledBufferCount = 0
    private var producerDidFinish = false
    private var didStartPlayback = false

    init(sampleRate: Double = 24_000) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw PocketTTSPlaybackError.audioFormatUnavailable
        }
        self.format = format
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    func prepare() throws {
        stop()
        producerDidFinish = false
        engine.prepare()
        try engine.start()
    }

    /// 排入一帧 24kHz 单声道 Float32 PCM。返回值表示这一帧是否触发了实际开播。
    @discardableResult
    func enqueue(_ samples: [Float]) throws -> Bool {
        guard !samples.isEmpty else { return false }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let destination = buffer.floatChannelData?[0] else {
            throw PocketTTSPlaybackError.audioBufferAllocationFailed
        }

        samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            destination.update(from: baseAddress, count: source.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let currentGeneration = generation
        scheduledBufferCount += 1
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bufferDidFinish(generation: currentGeneration)
            }
        }

        guard !didStartPlayback,
              scheduledBufferCount >= Self.prebufferFrameCount
        else { return false }
        startPlayback()
        return true
    }

    /// 返回值表示不足两帧的极短语音是否在收尾时才触发开播。
    @discardableResult
    func finishScheduling() -> Bool {
        producerDidFinish = true
        var startedNow = false
        if !didStartPlayback, scheduledBufferCount > 0 {
            startPlayback()
            startedNow = true
        }
        finishIfDrained()
        return startedNow
    }

    func stop() {
        generation &+= 1
        playerNode.stop()
        engine.stop()
        engine.reset()
        scheduledBufferCount = 0
        producerDidFinish = false
        didStartPlayback = false
    }

    private func bufferDidFinish(generation completedGeneration: UInt64) {
        guard completedGeneration == generation else { return }
        scheduledBufferCount = max(0, scheduledBufferCount - 1)
        finishIfDrained()
    }

    private func finishIfDrained() {
        guard producerDidFinish, scheduledBufferCount == 0 else { return }
        playerNode.stop()
        engine.stop()
        didStartPlayback = false
    }

    private func startPlayback() {
        didStartPlayback = true
        playerNode.play()
        NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: nil)
    }
}
