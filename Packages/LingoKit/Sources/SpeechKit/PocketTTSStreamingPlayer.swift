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

/// 只做很短的抗抖缓冲，不等待整句或估算整句生成速度。
enum PocketTTSPlaybackBufferPolicy {
    // Pocket 每帧 80ms；3 帧约 240ms，在快速开播和真机抖动之间取平衡。
    static let minimumBufferedDuration: TimeInterval = 0.24

    static func shouldStart(
        bufferedSampleCount: Int,
        sampleRate: Double,
        producerDidFinish: Bool
    ) -> Bool {
        guard bufferedSampleCount > 0, sampleRate > 0 else { return false }
        if producerDidFinish { return true }

        return Double(bufferedSampleCount) / sampleRate >= minimumBufferedDuration
    }
}

/// 独立 actor 隔离的流式 PCM 播放器。音频帧调度不经过 MainActor，避免界面
/// 动画或布局工作阻塞实时推理的消费端；所有已生成帧都会按顺序排入播放器。
actor PocketTTSStreamingPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double

    private var generation: UInt64 = 0
    private var scheduledBufferCount = 0
    private var scheduledSampleCount = 0
    private var producerDidFinish = false
    private var isPlaybackRunning = false
    private var hasBegunPlayback = false
    private var underrunCount = 0
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

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
        self.sampleRate = sampleRate
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
        scheduledSampleCount += samples.count
        let scheduledSamples = samples.count
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { [weak self] in
                await self?.bufferDidFinish(
                    generation: currentGeneration,
                    sampleCount: scheduledSamples
                )
            }
        }

        guard !isPlaybackRunning,
              PocketTTSPlaybackBufferPolicy.shouldStart(
                bufferedSampleCount: scheduledSampleCount,
                sampleRate: sampleRate,
                producerDidFinish: false
              )
        else { return false }
        return startPlayback()
    }

    /// 返回值表示短语音或慢设备是否在合成收尾时才首次开播。
    @discardableResult
    func finishScheduling() -> Bool {
        producerDidFinish = true
        var startedNow = false
        if !isPlaybackRunning,
           PocketTTSPlaybackBufferPolicy.shouldStart(
               bufferedSampleCount: scheduledSampleCount,
               sampleRate: sampleRate,
               producerDidFinish: true
           ) {
            startedNow = startPlayback()
        }
        finishIfDrained()
        return startedNow
    }

    func waitUntilFinished() async {
        guard !(producerDidFinish && scheduledBufferCount == 0) else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
        }
    }

    func stop() {
        generation &+= 1
        playerNode.stop()
        engine.stop()
        engine.reset()
        scheduledBufferCount = 0
        scheduledSampleCount = 0
        producerDidFinish = false
        isPlaybackRunning = false
        hasBegunPlayback = false
        underrunCount = 0
        resumeFinishWaiters()
    }

    private func bufferDidFinish(generation completedGeneration: UInt64, sampleCount: Int) {
        guard completedGeneration == generation else { return }
        scheduledBufferCount = max(0, scheduledBufferCount - 1)
        scheduledSampleCount = max(0, scheduledSampleCount - sampleCount)

        // 生产者未结束时不暂停或重置节点。AVAudioPlayerNode 会在队列暂空时
        // 渲染静音，并在下一帧排入后继续，确保长语音的帧不会被吞掉。
        if !producerDidFinish, isPlaybackRunning, scheduledBufferCount == 0 {
            underrunCount += 1
        }
        finishIfDrained()
    }

    func currentUnderrunCount() -> Int {
        underrunCount
    }

    private func finishIfDrained() {
        guard producerDidFinish, scheduledBufferCount == 0 else { return }
        playerNode.stop()
        engine.stop()
        isPlaybackRunning = false
        resumeFinishWaiters()
    }

    private func resumeFinishWaiters() {
        let waiters = finishWaiters
        finishWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    @discardableResult
    private func startPlayback() -> Bool {
        isPlaybackRunning = true
        playerNode.play()
        guard !hasBegunPlayback else { return false }
        hasBegunPlayback = true
        Task { @MainActor in
            NotificationCenter.default.post(name: .speechPlaybackDidBegin, object: nil)
        }
        return true
    }
}
