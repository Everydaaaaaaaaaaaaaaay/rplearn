import AVFoundation

/// AVAudioSession 单点管理：普通录音/播放/TTS 互斥；实时对话允许同时录放。
public actor AudioSessionCoordinator {
    public enum Mode: Sendable, Equatable {
        case idle
        case playback
        case record
        case conversation
    }

    public private(set) var mode: Mode = .idle
    private var activationID = UUID()

    public init() {}

    /// 切换音频会话模式；重复激活同一模式为幂等。
    public func activate(_ newMode: Mode, forceActivation: Bool = false) throws {
        activationID = UUID()
        // 系统中断后，逻辑模式可能未变，但实际会话需要重新激活。
        guard newMode != mode || forceActivation else { return }
        let session = AVAudioSession.sharedInstance()
        switch newMode {
        case .playback:
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        case .record:
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
        case .conversation:
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)
        case .idle:
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
        mode = newMode
    }

    public func deactivate() {
        activationID = UUID()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        mode = .idle
    }

    /// 短音频只释放自己取得的会话；后来的录音或语音播放不会被旧回调关闭。
    public func acquirePlayback() throws -> UUID {
        try activate(.playback, forceActivation: true)
        return activationID
    }

    public func releasePlayback(_ lease: UUID) {
        guard lease == activationID, mode == .playback else { return }
        deactivate()
    }
}
