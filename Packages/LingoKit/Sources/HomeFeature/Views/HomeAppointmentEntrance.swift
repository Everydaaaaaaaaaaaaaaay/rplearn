import BackendKit
import DesignSystem
import Observation
import PersistenceKit
import SwiftUI

@MainActor @Observable
final class HomeAppointmentPresentation {
    private(set) var appointment: BackendAppointment?
    private(set) var companion: CharacterDTO?
    private(set) var appointmentError = false

    func reload(using deps: HomeDependencies) async {
        guard let service = deps.appointments else { return }
        do {
            let list = try await service.appointments()
            let next = HomeHubPresentation.nextAppointment(in: list)
            var person: CharacterDTO?
            if let next { person = try? await deps.rosterStore.character(id: next.characterId) }
            guard !Task.isCancelled else { return }
            appointment = next
            companion = person
            appointmentError = false
        } catch is CancellationError {
        } catch { appointmentError = true }
    }
}

/// Only the appointment entrance observes its network result and companion.
struct HomeAppointmentEntrance: View {
    let model: HomeAppointmentPresentation
    let onOpenAppointment: (@MainActor (UUID) -> Void)?
    let onOpenDestination: @MainActor (HomeDestination) -> Void

    var body: some View {
        let appointment = model.appointment
        let companion = model.companion
        Button {
            if let appointment, let onOpenAppointment { onOpenAppointment(appointment.id) }
            else { onOpenDestination(.appointments) }
        } label: {
            HStack(spacing: 14) {
                if let companion {
                    AvatarBadge(name: companion.displayName, size: 48, imageName: companion.card.avatarAssetName,
                                remoteURL: companion.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                } else {
                    Image(systemName: "calendar").font(.system(size: 25, weight: .regular)).frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let appointment {
                        Text(appointment.status == "in_progress" ? "继续赴约" : "赴约")
                            .font(.caption).foregroundStyle(Color.dsSceneTextTertiary)
                        Text(appointment.displayTitle(companionName: companion?.displayName ?? "旅伴"))
                            .font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        Text("\(AppointmentDisplayTime.beijing(appointment.startsAt)) 北京时间 · \(appointment.displayCityName) \(appointment.placeName)")
                            .font(.caption).foregroundStyle(Color.dsSceneTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("赴约").font(.body.weight(.medium))
                    }
                    if model.appointmentError { Text("约定暂未更新，进入后可重试").font(.caption).foregroundStyle(Color.dsSceneTextSecondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.dsSceneTextTertiary)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .dsSceneGlass(radius: 22, interactive: true, legibility: .frosted)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(DSSceneEntranceButtonStyle()).accessibilityIdentifier("home.appointments")
    }
}
