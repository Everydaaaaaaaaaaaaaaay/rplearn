import DesignSystem
import SwiftUI

/// Draft edits update this control without rebuilding the scene, story, or choices.
struct AppointmentCustomActionInput: View {
    @Bindable var model: AppointmentModel
    @FocusState.Binding var inputFocused: Bool
    let sendingCustomAction: Bool
    let submitCustomAction: () -> Void
    private let ink = AppointmentStyle.ink

    private var canSubmitCustomAction: Bool {
        model.mayRespond && !sendingCustomAction && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.draft.count <= 500
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("", text: $model.draft,
                          prompt: Text("自定义你的行动").foregroundStyle(Puff.Palette.inkFaint), axis: .vertical)
                    .font(.puff(.body, Puff.Weight.body))
                    .lineLimit(1...2)
                    .padding(.leading, 20).padding(.vertical, 16)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(submitCustomAction)
                    .disabled(model.submitting || model.pending != nil || sendingCustomAction)
                    .accessibilityLabel("自定义你的行动")
                    .accessibilityIdentifier("appointment.input")
                Button(action: submitCustomAction) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: Puff.Weight.icon, design: .rounded))
                        .foregroundStyle(canSubmitCustomAction ? .white : Puff.Palette.inkFaint)
                        .frame(width: 44, height: 44)
                        .background(canSubmitCustomAction ? PuffCandy.sky.base : Puff.Palette.cloud, in: Circle())
                }
                .buttonStyle(.puffSquish)
                .disabled(!canSubmitCustomAction)
                .accessibilityLabel("提交行动")
                .accessibilityIdentifier("appointment.sendInput")
                .padding(8)
            }
            .background(Puff.Palette.cloud, in: RoundedRectangle(cornerRadius: Puff.Radius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Puff.Radius.large, style: .continuous)
                .strokeBorder(inputFocused ? PuffCandy.sky.base : Puff.Palette.line, lineWidth: inputFocused ? 2 : 1))
            if model.draft.count > 450 {
                Text("\(model.draft.count) / 500")
                    .font(.puff(.caption, Puff.Weight.label)).monospacedDigit()
                    .foregroundStyle(model.draft.count > 500 ? Puff.Palette.cherry : Puff.Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if model.offline {
                Text("已保存草稿，联网后可提交。").font(.puff(.footnote, Puff.Weight.label)).foregroundStyle(Puff.Palette.inkSoft)
            }
        }
        .onChange(of: model.draft) { _, _ in Task { await model.persistReading() } }
    }

}
