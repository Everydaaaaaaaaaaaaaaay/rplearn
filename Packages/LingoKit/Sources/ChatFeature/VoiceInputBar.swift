import DesignSystem
import SpeechKit
import SwiftUI

/// 「按住 说话」输入条 + 录音 HUD。手感对齐微信/QQ：
/// 按住开始录音，上滑 80pt 进入取消区（变红 + 触觉），松手发送/取消，60s 自动截断。
struct VoiceInputBar: View {
    let recorder: VoiceRecorder
    let onSend: (VoiceRecorder.Capture) -> Void

    @State private var isPressing = false
    @State private var startTask: Task<Void, Never>?
    @GestureState private var dragOffset: CGFloat = 0

    private var isRecording: Bool {
        if case .recording = recorder.state { return true }
        return false
    }

    private var inCancelZone: Bool {
        if case .recording(let inZone) = recorder.state { return inZone }
        return false
    }

    var body: some View {
        if case .failed(let message) = recorder.state {
            Button {
                Haptics.selection()
                recorder.resetFailure()
            } label: {
                barLabel(message)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(message)
            .accessibilityHint("双击后可重新按住录音")
        } else {
            barLabel(labelText)
                .gesture(pressGesture)
                .accessibilityLabel("语音输入")
                .accessibilityValue(labelText)
                .accessibilityHint(isRecording ? "双击发送录音" : "双击开始录音")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggleAccessibleRecording() }
                .accessibilityAction(named: "取消录音") {
                    Task { await recorder.cancelRecording() }
                }
        }
    }

    private func barLabel(_ text: String) -> some View {
        Text(text)
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isRecording
                    ? (inCancelZone ? Color.dsDanger.opacity(0.9) : Color.dsSky.opacity(0.9))
                    : Color.dsBubbleIncoming,
                in: RoundedRectangle(cornerRadius: DSRadius.bubble, style: .continuous)
            )
            .foregroundStyle(isRecording ? .white : .primary)
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.bubble, style: .continuous))
            .overlay(alignment: .top) {
                if isRecording {
                    recordingHUD
                        .offset(y: -120)
                }
            }
            .scaleEffect(isRecording ? 0.985 : 1)
            .animation(DSAnimation.feedback, value: isRecording)
            .animation(DSAnimation.feedback, value: inCancelZone)
    }

    private var labelText: String {
        switch recorder.state {
        case .recording(let inZone): inZone ? "松开取消" : "松开发送 · 上滑取消"
        case .transcribing: "识别中…"
        case .denied: "请在设置中允许麦克风与语音识别"
        case .failed(let message): message
        case .idle: "按住 说话"
        }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onChanged { value in
                if !isPressing {
                    isPressing = true
                    Haptics.impact(.medium)
                    startTask?.cancel()
                    startTask = Task { await recorder.startRecording() }
                } else {
                    let nowInZone = value.translation.height < -80
                    if nowInZone != inCancelZone {
                        Haptics.impact(.light)
                        recorder.setCancelZone(nowInZone)
                    }
                }
            }
            .onEnded { value in
                isPressing = false
                startTask?.cancel()
                startTask = nil
                let cancelled = value.translation.height < -80
                Task {
                    if cancelled, recorder.pendingAutoCapture == nil {
                        await recorder.cancelRecording()
                    } else if let capture = await recorder.finishRecording() {
                        onSend(capture)
                    }
                }
            }
    }

    private var recordingHUD: some View {
        VStack(spacing: 8) {
            levelBars
            Text(String(format: "%.0f″ / 60″", recorder.elapsed))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
            Text(inCancelZone ? "松开手指，取消发送" : "上滑取消")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .background(
            (inCancelZone ? Color.dsDanger : Color.black).opacity(0.78),
            in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
        )
    }

    private func toggleAccessibleRecording() {
        if isRecording {
            Task {
                if let capture = await recorder.finishRecording() {
                    onSend(capture)
                }
            }
        } else {
            startTask?.cancel()
            startTask = Task { await recorder.startRecording() }
        }
    }

    private var levelBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                let scale = max(0.15, min(1, recorder.level * Double.random(in: 0.6...1.3)))
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: 6 + 22 * scale)
                    .opacity(index % 2 == 0 ? 1 : 0.7)
            }
        }
        .animation(.linear(duration: 0.1), value: recorder.level)
    }
}

/// 语音条气泡内容：播放按钮 + 波形示意 + 时长；点击回放。
struct VoiceBubbleContent: View {
    let message: VoiceBubbleModel
    let isPlaying: Bool
    let showTranscript: Bool
    let textColor: Color?
    let onTogglePlay: () -> Void

    struct VoiceBubbleModel {
        let duration: Double
        let transcript: String
        let hasAudio: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.hasAudio {
                Button(action: onTogglePlay) {
                    playbackRow
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "暂停语音消息" : "播放语音消息")
                .accessibilityValue("\(Int(message.duration.rounded())) 秒")
            } else {
                playbackRow
            }
            if showTranscript {
                Text(message.transcript)
                    .font(.footnote)
                    .foregroundStyle((textColor ?? .primary).opacity(0.85))
            }
        }
    }

    private var playbackRow: some View {
        HStack(spacing: 8) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.title3)
            waveform
            Text("\(Int(message.duration.rounded()))″")
                .font(.subheadline.monospacedDigit())
        }
        .foregroundStyle(textColor ?? .primary)
        .contentShape(Rectangle())
    }

    private var waveform: some View {
        // 波形宽度随时长增长（10s 封顶），模拟微信语音条
        let barCount = min(18, 6 + Int(message.duration))
        return HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill((textColor ?? .primary).opacity(isPlaying ? 1 : 0.75))
                    .frame(width: 2.5, height: CGFloat([8, 14, 10, 18, 12, 16][index % 6]))
            }
        }
    }
}
