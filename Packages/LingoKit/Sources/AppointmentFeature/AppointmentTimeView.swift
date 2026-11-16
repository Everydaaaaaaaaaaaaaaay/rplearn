import BackendKit
import SwiftUI

struct AppointmentTimeView: View {
    let appointment: BackendAppointment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "calendar").font(.footnote)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    beijingTime
                    localTime
                }
            } else {
                beijingTime
                Spacer(minLength: 4)
                localTime
            }
        }
        .foregroundStyle(AppointmentStyle.ink.opacity(0.7))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var beijingTime: some View {
        Text(AppointmentDisplayTime.beijing(appointment.startsAt))
            .font(.footnote)
            .accessibilityLabel("北京时间，\(AppointmentDisplayTime.beijing(appointment.startsAt))")
            .accessibilityIdentifier("appointment.beijingTime")
    }

    private var localTime: some View {
        Text(AppointmentDisplayTime.local(appointment.startsAt, city: appointment.cityName, timeZone: appointment.timeZone))
            .font(.caption).foregroundStyle(AppointmentStyle.ink.opacity(0.6))
            .accessibilityIdentifier("appointment.localTime")
    }
}
