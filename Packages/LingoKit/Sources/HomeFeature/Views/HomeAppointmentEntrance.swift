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
            HStack(spacing: Puff.Space.s) {
                if let companion {
                    PuffAvatar(name: companion.displayName, size: 52, imageName: companion.card.avatarAssetName,
                               remoteURL: companion.card.avatarRemoteURL.flatMap(URL.init(string:)))
                } else {
                    PuffIconBubble("calendar", candy: .bubblegum, size: 52)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let appointment {
                        let zone = AppointmentDisplayTime.userZone(appointment.userTimeZone)
                        let date = AppointmentDisplayTime.scheduled(appointment.startsAt, zone: zone)
                        let zoneLabel = AppointmentDisplayTime.zoneLabel(zone)
                        PuffTag(appointment.status == "in_progress" ? "继续赴约" : "赴约",
                                systemImage: "heart.fill", candy: .bubblegum)
                        Text(appointment.displayTitle(companionName: companion?.displayName ?? "旅伴"))
                            .font(.puff(.headline, .heavy))
                            .foregroundStyle(Puff.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(date) \(zoneLabel) · \(appointment.displayCityName) \(appointment.placeName)")
                            .font(.puff(.caption, .semibold))
                            .foregroundStyle(Puff.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("赴约")
                            .font(.puff(.headline, .heavy))
                            .foregroundStyle(Puff.Palette.ink)
                    }
                    if model.appointmentError {
                        Text("约定暂未更新")
                            .font(.puff(.caption, .bold))
                            .foregroundStyle(Puff.Palette.cherry)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Puff.Palette.inkFaint)
            }
            .padding(Puff.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PuffCardButtonStyle(radius: Puff.Radius.large))
        .accessibilityIdentifier("home.appointments")
    }
}
