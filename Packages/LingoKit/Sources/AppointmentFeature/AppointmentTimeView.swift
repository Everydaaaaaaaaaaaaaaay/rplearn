import DesignSystem
import BackendKit
import SwiftUI

struct AppointmentTimeView: View {
    let appointment: BackendAppointment

    var body: some View {
        let zone = AppointmentDisplayTime.userZone(appointment.userTimeZone)
        let date = AppointmentDisplayTime.scheduled(appointment.startsAt, zone: zone)
        let label = AppointmentDisplayTime.zoneLabel(zone)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "calendar").accessibilityHidden(true)
            Text("\(date) · \(label)")
                .accessibilityLabel("\(label)，\(date)")
                .accessibilityIdentifier("appointment.userTime")
        }
        .font(.puff(.footnote, Puff.Weight.label))
        .foregroundStyle(Puff.Palette.inkSoft)
        .fixedSize(horizontal: false, vertical: true)
    }
}
