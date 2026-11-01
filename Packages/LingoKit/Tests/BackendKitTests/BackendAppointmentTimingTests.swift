import Foundation
import Testing
@testable import BackendKit

@Suite("Appointment request timing")
struct BackendAppointmentTimingTests {
    private struct Store: AuthCredentialStore {
        func load() throws -> StoredAuthCredential? { nil }
        func remove() throws {}
        func save(_ credential: StoredAuthCredential) throws {}
    }
    private actor Transport: BackendTransport {
        var requests: [URLRequest] = []
        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            requests.append(request)
            return BackendTransportResponse(data: Data(#"{"ok":true}"#.utf8), headers: [:], statusCode: 200)
        }
    }
    private struct Probe: Decodable, Sendable { let ok: Bool }

    @Test("the appointment resource ceiling covers its request budget without changing ordinary sessions")
    func resourceBudgets() {
        let appointment = URLSessionBackendTransport.appointmentSessionConfiguration()
        let ordinary = URLSessionBackendTransport.defaultSessionConfiguration()
        #expect(appointment.timeoutIntervalForRequest == 170)
        #expect(appointment.timeoutIntervalForResource == 180)
        #expect(ordinary.timeoutIntervalForRequest == 30)
        #expect(ordinary.timeoutIntervalForResource == 120)
        #expect(!appointment.waitsForConnectivity)
    }

    @Test("generation and pending-review reads have bounded extended waits; ordinary reads retain the normal limit")
    func requestBudgets() async throws {
        let transport = Transport()
        let client = BackendClient(configuration: BackendConfiguration(baseURL: URL(string: "https://example.com")!), credentialStore: Store(), transport: transport)
        let id = "019c0123-4567-789a-8bcd-ef01234567f0"
        let cases: [(String, TimeInterval)] = [
            ("/v1/appointments/detect", 170),
            ("/v1/appointments/\(id)", 170),
            ("/v1/appointments/\(id)/start", 170),
            ("/v1/appointments/\(id)/choices", 170),
            ("/v1/appointments/\(id)/settlement", 170),
            ("/v1/appointments", 30),
            ("/v1/appointments/\(id)/cancel", 30),
            ("/v1/appointments/\(id)/settle", 30),
            ("/v1/probe", 30),
            ("/v1/grammar/analysis", 75),
        ]
        for (path, _) in cases { let _: Probe = try await client.publicGet(path) }
        let requests = await transport.requests
        #expect(requests.map(\.timeoutInterval) == cases.map(\.1))
    }
}
