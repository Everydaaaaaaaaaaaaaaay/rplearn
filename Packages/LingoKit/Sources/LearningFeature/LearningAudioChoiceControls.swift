import BackendKit
import SwiftUI

struct LearningAudioChoiceControls: View {
    let question: LearningQuestion
    let attemptID: UUID
    let audio: LearningAudioOptionsModel
    @Binding var selection: String?
    let tint: Color
    let selectionDisabled: Bool
    var selectionPrefix: String = "选择声音"

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array((question.audioOptions ?? []).enumerated()), id: \.element.id) { index, option in
                let player = audio.players[option.id]
                let playing = player?.state == .playing
                let loading = player == nil || player?.state == .loading || player?.state == .idle
                HStack(spacing: 12) {
                    Button {
                        if player?.state == .failed {
                            Task { await audio.retry(option, attemptID: attemptID, questionID: question.id) }
                        } else { audio.play(option.id) }
                    } label: {
                        Group {
                            if loading { ProgressView() }
                            else { Image(systemName: playing ? "stop.fill" : player?.state == .failed ? "arrow.clockwise" : "play.fill").font(.system(size: 20, weight: .semibold)) }
                        }.frame(width: 48, height: 48)
                            .background(tint.opacity(0.12), in: Circle())
                    }
                    .disabled(loading)
                    .accessibilityLabel("\(playing ? "停止" : player?.state == .failed ? "重新载入" : "播放")声音 \(index + 1)")
                    .accessibilityValue(player?.hasListened == true ? "已听完" : "未听完")
                    .accessibilityIdentifier("learning.sound.play.\(option.id)")
                    Button { audio.play(option.id, slow: true) } label: {
                        Image(systemName: "tortoise").font(.system(size: 22)).frame(width: 44, height: 48)
                    }.disabled(loading || player?.state == .failed)
                        .accessibilityLabel("慢速播放声音 \(index + 1)")
                        .accessibilityIdentifier("learning.sound.slow.\(option.id)")
                    Button { selection = option.id } label: {
                        HStack {
                            Text("\(index + 1)").font(.title3.monospacedDigit())
                            if player?.hasListened == true { Image(systemName: "checkmark").font(.system(size: 13, weight: .medium)) }
                            Spacer(minLength: 8)
                            Image(systemName: selection == option.id ? "checkmark.circle.fill" : "circle").font(.system(size: 24))
                        }.frame(minHeight: 52).contentShape(Rectangle())
                    }.disabled(selectionDisabled).accessibilityLabel("\(selectionPrefix) \(index + 1)")
                        .accessibilityAddTraits(selection == option.id ? .isSelected : [])
                        .accessibilityIdentifier("learning.sound.select.\(option.id)")
                }.padding(.vertical, 16)
                Divider()
            }
        }.buttonStyle(.plain).foregroundStyle(tint)
    }
}
