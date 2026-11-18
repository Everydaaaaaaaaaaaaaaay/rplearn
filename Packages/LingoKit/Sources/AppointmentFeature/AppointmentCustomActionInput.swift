import DesignSystem
import SwiftUI

/// Draft edits update this control without rebuilding the photo, story, or choices.
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
                          prompt: Text("自定义你的行动").foregroundStyle(ink.opacity(0.45)), axis: .vertical)
                    .font(.body)
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(canSubmitCustomAction ? .white : ink.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .background(canSubmitCustomAction ? ink : ink.opacity(0.08), in: Circle())
                }
                .buttonStyle(DSSceneEntranceButtonStyle())
                .disabled(!canSubmitCustomAction)
                .accessibilityLabel("提交行动")
                .accessibilityIdentifier("appointment.sendInput")
                .padding(8)
            }
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(ink.opacity(inputFocused ? 0.30 : 0.14)))
            if model.draft.count > 450 {
                Text("\(model.draft.count) / 500")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(model.draft.count > 500 ? Color.red : ink.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if model.offline {
                Text("已保存草稿，联网后可提交。").font(.footnote).foregroundStyle(ink.opacity(0.65))
            }
        }
        .onChange(of: model.draft) { _, _ in Task { await model.persistReading() } }
    }

}
