#if DEBUG
import BackendKit
import Foundation
import PersistenceKit

/// Explicitly isolated local fixture. It never calls the backend or opens the user's cache.
extension AppointmentListView {
    public nonisolated static let previewAppointmentID = UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!
    public nonisolated static let previewCharacterID = UUID(uuidString: "a0000000-0000-4000-8000-000000000002")!

    static var previewCharacterCards: [UUID: CharacterCard] {
        [previewCharacterID: CharacterCard(name: "Oliver", age: 25, gender: .male, nationality: "UK",
                                          regionID: "london", occupation: "", hobbies: [], appearance: "",
                                          personality: "", avatarAssetName: "avatar_oliver")]
    }

    public static func previewFixture(scenario: String = "confirmed", readingServices: AppointmentReadingServices? = nil, onClose: (() -> Void)? = nil, onChat: @escaping (UUID) -> Void = { _ in }, onMemory: @escaping (UUID) -> Void = { _ in }) -> AppointmentListView {
        AppointmentListView(service: AppointmentPreviewService(scenario: scenario), currentCityID: "london", storageNamespace: "debug-fixture-\(UUID().uuidString)", initialAppointmentID: scenario == "list" ? nil : previewAppointmentID, readingServices: readingServices, onClose: onClose, characterName: { _ in "Oliver" }, characterCards: previewCharacterCards, onChat: onChat, onMemory: onMemory)
    }
}

actor AppointmentPreviewService: AppointmentServing {
    private var value: [String: Any]
    private var receipts: [UUID: BackendAppointmentDetail] = [:]
    private let scenario: String
    private var failed = false

    init(scenario: String) {
        self.scenario = scenario
        let active = ["active", "retry", "offline", "conflict"].contains(scenario)
        let completed = ["completed", "pending", "zero", "negative"].contains(scenario)
        value = [
            "appointment": [
                "id": AppointmentListView.previewAppointmentID.uuidString,
                "characterId": AppointmentListView.previewCharacterID.uuidString,
                "title": "和Oliver一起散步",
                "cityId": "london", "cityName": "伦敦", "timeZone": "Europe/London",
                "placeName": "南岸（本地演示）",
                "startsAt": "2026-11-01T15:00:00Z", "endsAt": "2026-11-01T16:00:00Z",
                "windowOpensAt": "2026-11-01T14:30:00Z", "windowClosesAt": "2026-11-01T17:00:00Z",
                "status": completed ? "completed" : active ? "in_progress" : "confirmed", "revision": active || completed ? 1 : 0
            ],
            "serverNow": scenario == "before-window" ? "2026-11-01T14:29:59Z" : "2026-11-01T15:00:00Z",
            "session": NSNull(), "summary": NSNull()
        ]
        if active || completed {
            value["session"] = ["id": "a0000000-0000-4000-8000-000000000003", "blocks": [Self.block(index: 0, ending: false)], "decisions": []] as [String: Any]
        }
        if completed {
            value["summary"] = Self.summary(scenario: scenario)
            var session = value["session"] as! [String: Any]
            session["blocks"] = [Self.block(index: 0, ending: false), Self.block(index: 1, ending: true)]
            session["decisions"] = [["id": "fixture-decision", "blockId": "fixture-block-0", "input": "Could we sit by the water?", "custom": true, "outcome": "你提出在水边坐一会，Oliver 同意了这个安排。", "createdAt": "2026-11-01T15:02:00Z"]]
            value["session"] = session
        }
    }

    func appointments() async throws -> BackendAppointmentList {
        let detail = try decoded()
        return .init(appointments: [detail.appointment], serverNow: detail.serverNow)
    }

    func appointment(_ id: UUID) async throws -> BackendAppointmentDetail {
        if scenario == "offline" && failed { throw BackendClientError.transport("Local fixture offline") }
        if scenario == "reconnect" && !failed {
            failed = true
            throw BackendClientError.transport("Local fixture connection interrupted")
        }
        let detail = try decoded()
        if scenario == "before-window" { value["serverNow"] = "2026-11-01T14:30:00Z" }
        return detail
    }

    func appointmentCommand(_ id: UUID, action: BackendAppointmentAction, request: BackendAppointmentCommand) async throws -> BackendAppointmentDetail {
        if let receipt = receipts[request.commandId] { return receipt }
        if scenario == "retry" && !failed { failed = true; throw BackendClientError.transport("Local fixture lost response") }
        if scenario == "conflict" && !failed { failed = true; throw BackendClientError.api(code: "APPOINTMENT_VERSION_CONFLICT", message: "Local fixture conflict", requestID: nil, status: 409) }
        if scenario == "offline" { failed = true; throw BackendClientError.transport("Local fixture offline") }
        var appointment = value["appointment"] as! [String: Any]
        if action == .start {
            appointment["status"] = "in_progress"
            value["session"] = ["id": "a0000000-0000-4000-8000-000000000003", "blocks": [Self.block(index: 0, ending: false)], "decisions": []] as [String: Any]
        } else if action == .cancel { appointment["status"] = "cancelled" }
        else {
            var session = value["session"] as! [String: Any]
            var blocks = session["blocks"] as! [[String: Any]]
            var decisions = session["decisions"] as! [[String: Any]]
            let input = request.input ?? (request.finish == true ? "今天就到这里" : request.choiceId == "quiet" ? "Let's sit quietly for a moment." : "Shall we walk along the water?")
            decisions.append(["id": "fixture-decision-\(decisions.count)", "blockId": blocks.last!["id"]!, "input": input, "custom": request.input != nil, "outcome": request.finish == true ? "你提出告别，Oliver 尊重你的安排，两人自然结束了这次相处。" : "你提出「\(input)」，Oliver 与你商量下一步，并按双方同意的安排继续。", "createdAt": "2026-11-01T15:02:00Z"])
            blocks.append(Self.block(index: blocks.count, ending: request.finish == true, response: request.input))
            session["blocks"] = blocks; session["decisions"] = decisions; value["session"] = session
            if request.finish == true { appointment["status"] = "completed"; value["summary"] = Self.summary(scenario: scenario) }
        }
        appointment["revision"] = (appointment["revision"] as! Int) + 1
        value["appointment"] = appointment
        let detail = try decoded(); receipts[request.commandId] = detail; return detail
    }

    private func decoded() throws -> BackendAppointmentDetail {
        try JSONDecoder().decode(BackendAppointmentDetail.self, from: JSONSerialization.data(withJSONObject: value))
    }

    private static func block(index: Int, ending: Bool, response: String? = nil) -> [String: Any] {
        ["id": "fixture-block-\(index)", "sequence": index, "location": "南岸 · 水边步道", "ending": ending,
         "beats": [
            ["speaker": "narrator", "english": ending ? "You reach the path back to the bridge. There is no need to hurry the goodbye." : "A folded map flutters on the bench. Oliver catches its corner before it slips away.", "chinese": ending ? "你们走到通往桥边的小路，告别不必匆忙。" : "长椅上的折叠地图被风掀起，Oliver 伸手按住一角。"],
            ["speaker": "character", "english": ending ? "I'm glad we had this little bit of time. See you around." : response.map { "You suggested: “\($0)”. Let's talk through how we could do that." } ?? "We could follow the river, or find somewhere to sit. What would you prefer?", "chinese": ending ? "很高兴我们有了这一小段相处的时间。回头见。" : response.map { "你提议「\($0)」。我们可以商量怎样安排。" } ?? "我们可以沿河走走，也可以找个地方坐下。你想怎样？"]
         ],
         "choices": ending ? [] : [["id": "walk", "english": "Shall we walk along the water?", "chinese": "沿着水边走走吧？"], ["id": "quiet", "english": "Let's sit quietly for a moment.", "chinese": "安静坐一会吧。"]]]
    }

    private static func summary(scenario: String) -> [String: Any] {
        let delta = scenario == "zero" ? 0 : scenario == "negative" ? -1 : 1
        return ["title": "和Oliver一起散步", "reflection": "你们在南岸的水边坐了一会，随后沿步道走回桥边。", "affinity": ["status": scenario == "pending" ? "pending" : "settled", "before": 30, "after": 30 + delta, "delta": delta, "reason": "本地演示 · 相处自然，彼此尊重"], "memories": [["id": "fixture-memory", "content": "演示：你与 Oliver 在伦敦南岸商量散步的安排。", "status": "active"]]]
    }
}
#endif
