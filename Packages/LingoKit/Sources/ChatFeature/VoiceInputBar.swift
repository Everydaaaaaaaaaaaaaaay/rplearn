import SpeechKit
import SwiftUI

/// 「按住 说话」输入条 + 录音 HUD。手感对齐微信/QQ：
/// 按住开始录音，上滑 80pt 进入取消区（变红 + 触觉），松手发送/取消，60s 自动截断。
struct VoiceInputBar: View {
    let recorder: VoiceRecorder
    let onSend: (VoiceRecorder.Capture) -> Void

    @State private var isPressing = false
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
        Text(labelText)
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isRecording ? (inCancelZone ? Color.red.opacity(0.85) : Color.accentColor.opacity(0.85)) : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .foregroundStyle(isRecording ? .white : .primary)
            .gesture(pressGesture)
            .overlay(alignment: .top) {
                if isRecording {
                    recordingHUD
                        .offset(y: -120)
                }
            }
            .animation(.snappy(duration: 0.18), value: isRecording)
            .animation(.snappy(duration: 0.18), value: inCancelZone)
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
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await recorder.startRecording() }
                } else {
                    let nowInZone = value.translation.height < -80
                    if nowInZone != inCancelZone {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        recorder.setCancelZone(nowInZone)
                    }
                }
            }
            .onEnded { value in
                isPressing = false
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
            (inCancelZone ? Color.red : Color.black).opacity(0.75),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
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
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
                waveform
                Text("\(Int(message.duration.rounded()))″")
                    .font(.subheadline.monospacedDigit())
            }
            .foregroundStyle(textColor ?? .primary)
            .contentShape(Rectangle())
            .onTapGesture {
                if message.hasAudio {
                    onTogglePlay()
                }
            }
            if showTranscript {
                Text(message.transcript)
                    .font(.footnote)
                    .foregroundStyle((textColor ?? .primary).opacity(0.85))
            }
        }
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
