import BackendKit
import Foundation
import Testing
@testable import HomeFeature

struct HomeHubPresentationTests {
    @Test func excludesFinishedCancelledAndExpiredAppointments() throws {
        let future = try item(status: "confirmed", startsAt: "2026-11-17T15:00:00Z")
        let items = [
            try item(status: "completed", startsAt: "2026-11-17T10:00:00Z"),
            try item(status: "cancelled", startsAt: "2026-11-17T11:00:00Z"),
            try item(status: "confirmed", startsAt: "2026-11-15T12:00:00Z", closesAt: "2026-11-15T13:00:00Z"),
            future,
        ]
        #expect(HomeHubPresentation.nextAppointment(in: .init(appointments: items, serverNow: "2026-11-16T12:00:00Z"))?.id == future.id)
    }

    @Test func ongoingAppointmentTakesPriority() throws {
        let ongoing = try item(status: "in_progress", startsAt: "2026-11-17T15:00:00Z")
        let future = try item(status: "confirmed", startsAt: "2026-11-17T10:00:00Z")
        #expect(HomeHubPresentation.nextAppointment(in: .init(appointments: [future, ongoing], serverNow: "2026-11-16T12:00:00Z"))?.id == ongoing.id)
    }

    @Test func legacyTimeOffsetsSortByActualInstant() throws {
        let earlier = try item(status: "confirmed", startsAt: "2026-11-17T07:00:00+03:00")
        let later = try item(status: "confirmed", startsAt: "2026-11-17T05:00:00Z")
        #expect(HomeHubPresentation.nextAppointment(in: .init(appointments: [later, earlier], serverNow: "2026-11-16T12:00:00Z"))?.id == earlier.id)
    }

    @Test func emptyOrUntrustedSnapshotHasNoInventedAppointment() {
        #expect(HomeHubPresentation.nextAppointment(in: .init(appointments: [], serverNow: "2026-11-16T12:00:00Z")) == nil)
        #expect(HomeHubPresentation.nextAppointment(in: .init(appointments: [], serverNow: "invalid")) == nil)
    }

    private func item(status: String, startsAt: String, closesAt: String = "2026-11-18T00:00:00Z") throws -> BackendAppointment {
        let value: [String: Any] = [
            "id": UUID().uuidString, "characterId": UUID().uuidString,
            "title": "一起散步", "cityId": "london", "cityName": "London", "timeZone": "Europe/London",
            "placeName": "南岸", "startsAt": startsAt, "endsAt": closesAt,
            "windowOpensAt": startsAt, "windowClosesAt": closesAt, "status": status, "revision": 0,
        ]
        return try JSONDecoder().decode(BackendAppointment.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
