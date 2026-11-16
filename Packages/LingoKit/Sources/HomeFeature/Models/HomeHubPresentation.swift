import BackendKit
import Foundation

enum HomeHubPresentation {
    static func nextAppointment(in list: BackendAppointmentList) -> BackendAppointment? {
        guard let now = AppointmentDisplayTime.date(list.serverNow) else { return nil }
        return list.appointments.filter { item in
            if item.status == "in_progress" { return true }
            guard item.status == "confirmed", let closes = AppointmentDisplayTime.date(item.windowClosesAt) else { return false }
            return closes >= now
        }.sorted { lhs, rhs in
            if (lhs.status == "in_progress") != (rhs.status == "in_progress") { return lhs.status == "in_progress" }
            return (AppointmentDisplayTime.date(lhs.startsAt) ?? .distantFuture)
                < (AppointmentDisplayTime.date(rhs.startsAt) ?? .distantFuture)
        }.first
    }
}
