#if DEBUG
import AVFoundation
import SpeechKit
import SwiftUI

/// Temporary audition tool; no model downloads or persistent voice preferences.
struct SupertonicVoicePreviewSheet: View {
    let audio: NarrativeAudioPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: SupertonicPreviewVoice?
    @State private var began = false
    @State private var status = "轻点音色开始试听"

    private let text = "After the rain, would you rather walk through the park or read a story in the bookshop? I thought we could meet there at half past four."

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("全部使用 Supertonic · 相同文本 · 1× 语速\n不改变角色音色，也不预设英音或美音标签。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(text).font(.body)
                    Text(status).font(.subheadline).accessibilityIdentifier("voicePreview.status")
                }
                voiceSection("男声", voices: Array(SupertonicPreviewVoice.allCases.prefix(5)))
                voiceSection("女声", voices: Array(SupertonicPreviewVoice.allCases.suffix(5)))
            }
            .navigationTitle("音色试听")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { stop(); dismiss() }.accessibilityIdentifier("voicePreview.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("停止", systemImage: "stop.fill") { stop() }
                        .disabled(selected == nil).accessibilityIdentifier("voicePreview.stop")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onDisappear { stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .speechPlaybackDidBegin)) { _ in
            guard let selected else { return }
            began = true
            status = "正在播放 \(selected.rawValue) · 再点一次可停止"
        }
        .onChange(of: audio.completedID) { _, id in
            guard let selected, id == "preview.\(selected.rawValue)" else { return }
            status = began ? "\(selected.rawValue) 试听结束" : "\(selected.rawValue) 未能播放，请重试；不会替换为系统声音"
            self.selected = nil
        }
    }

    private func voiceSection(_ title: String, voices: [SupertonicPreviewVoice]) -> some View {
        Section(title) {
            ForEach(voices, id: \.self) { voice in
                Button {
                    guard selected != voice else { stop(); return }
                    selected = voice
                    began = false
                    status = "正在合成 \(voice.rawValue)…"
                    audio.play(id: "preview.\(voice.rawValue)",
                               request: SpeechRequest(text: text, language: "en", engine: .supertonic3, previewVoice: voice),
                               rainVolume: 0, pageTurn: false)
                } label: {
                    HStack {
                        Text(voice.rawValue).monospaced().fontWeight(.medium)
                        if voice == .f5 { Text("Nora 当前音色").foregroundStyle(.secondary) }
                        if voice == .m2 { Text("Oliver 当前音色").foregroundStyle(.secondary) }
                        if voice == .f1 { Text("旁白当前音色").foregroundStyle(.secondary) }
                        Spacer()
                        if selected == voice && !began { ProgressView() }
                        else { Image(systemName: selected == voice ? "stop.circle.fill" : "play.circle") }
                    }
                    .frame(minHeight: 40).contentShape(Rectangle())
                }
                .accessibilityIdentifier("voicePreview.\(voice.rawValue)")
            }
        }
    }

    private func stop() {
        audio.stop()
        selected = nil
        began = false
        status = "已停止"
    }
}
#endif
