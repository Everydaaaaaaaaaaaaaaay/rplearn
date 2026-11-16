#if DEBUG
import DesignSystem
import SwiftUI

/// Runs the production summary with an isolated local appointment session.
public struct AppointmentSummaryDesignPreview: View {
    private let onClose: () -> Void
    @State private var model: AppointmentModel

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: AppointmentModel(id: AppointmentListView.previewAppointmentID,
            service: AppointmentPreviewService(scenario: "confirmed"),
            cache: AppointmentCaches.account("summary-design-\(UUID().uuidString)")))
    }

    public var body: some View {
        NavigationStack {
            Group {
                if model.detail?.summary != nil {
                    AppointmentSummaryView(model: model, characterName: { _ in "Oliver" },
                                           onChat: { _ in onClose() }, onMemory: { _ in onClose() }, onBack: onClose)
                } else if let error = model.error {
                    AppointmentErrorView(message: error, loading: model.loading || model.submitting) {
                        Task { await seed() }
                    }.padding(24)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.background(AppointmentStyle.canvas)
        }
        .environment(\.appointmentCharacterCards, AppointmentListView.previewCharacterCards)
        .preferredColorScheme(.light)
        .task { await seed() }
    }

    private func seed() async {
        guard model.detail?.summary == nil else { return }
        await model.load()
        if model.pending != nil { await model.retry() }
        if model.detail?.appointment.status == "confirmed" { await model.submit(action: .start) }
        guard model.error == nil, model.pending == nil else { return }
        if model.detail?.session?.decisions.isEmpty == true {
            await model.submit(action: .choice, input: "Could we sit by the water? 我想安静坐一会。")
        }
        guard model.error == nil, model.pending == nil else { return }
        if model.detail?.appointment.status == "in_progress" { await model.submit(action: .choice, finish: true) }
    }
}
#endif
