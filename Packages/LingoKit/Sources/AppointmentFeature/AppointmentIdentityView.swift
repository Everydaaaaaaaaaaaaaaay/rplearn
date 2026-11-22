import BackendKit
import DesignSystem
import PersistenceKit
import SwiftUI

extension EnvironmentValues {
    @Entry var appointmentCharacterCards: [UUID: CharacterCard] = [:]
}

struct AppointmentAvatarView: View {
    let characterID: UUID
    let name: String
    var size: CGFloat = 28
    @Environment(\.appointmentCharacterCards) private var cards

    var body: some View {
        PuffAvatar(name: name, size: size, imageName: cards[characterID]?.avatarAssetName,
                   remoteURL: cards[characterID]?.avatarRemoteURL.flatMap(URL.init(string:)))
            .accessibilityIdentifier("appointment.avatar.\(characterID.uuidString.lowercased())")
    }
}

struct AppointmentIdentityView: View {
    let appointment: BackendAppointment
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AppointmentAvatarView(characterID: appointment.characterId, name: name, size: 52)
                VStack(alignment: .leading, spacing: 6) {
                    Text(appointment.displayTitle(companionName: name))
                        .font(.puff(.title3, Puff.Weight.title)).foregroundStyle(Puff.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("appointment.title")
                    Label(appointment.placeName, systemImage: "mappin")
                        .font(.puff(.footnote, Puff.Weight.label)).foregroundStyle(Puff.Palette.inkSoft)
                }
            }
            AppointmentTimeView(appointment: appointment)
        }
    }
}
