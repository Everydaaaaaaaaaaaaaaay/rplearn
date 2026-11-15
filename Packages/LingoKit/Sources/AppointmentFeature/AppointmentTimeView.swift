import BackendKit
import SwiftUI

struct AppointmentTimeView: View {
    let appointment: BackendAppointment

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppointmentDisplayTime.beijing(appointment.startsAt))
                .font(.subheadline.weight(.medium))
                .accessibilityLabel("北京时间，\(AppointmentDisplayTime.beijing(appointment.startsAt))")
                .accessibilityIdentifier("appointment.beijingTime")
            Text(AppointmentDisplayTime.local(appointment.startsAt, city: appointment.cityName, timeZone: appointment.timeZone))
                .font(.caption).foregroundStyle(AppointmentStyle.ink.opacity(0.6))
                .accessibilityIdentifier("appointment.localTime")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
