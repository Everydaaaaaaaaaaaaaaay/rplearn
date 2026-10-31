import BackendKit
import DomainKit
import Foundation

struct CityOutingArchive: Codable, Sendable {
    let version: Int
    let runID: UUID
    let releaseID: String
    let place: BackendActivityPlace
    var snapshot: BackendOuting?
    var pending: [BackendOutingOperation]
    var cancelled: Bool? = nil

    init(place: BackendActivityPlace, releaseID: String) {
        version = 1; runID = UUID(); self.releaseID = releaseID; self.place = place
        snapshot = nil; pending = []
    }
    init(restoring snapshot: BackendOuting) {
        version = 1; runID = snapshot.runId; releaseID = snapshot.releaseId
        place = .init(id: snapshot.placeId, titleZh: snapshot.placeTitleZh, category: "", photo: snapshot.photo)
        self.snapshot = snapshot; pending = []
    }

    static func key(namespace: String) -> String {
        "lingotrip.place-outing.v1." + Data(namespace.utf8).base64EncodedString()
    }
    static func load(namespace: String, defaults: UserDefaults = .standard) throws -> Self? {
        guard let data = defaults.data(forKey: key(namespace: namespace)) else { return nil }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1 else { throw ActivityJournal.JournalError.unsupportedVersion }
        if let snapshot = value.snapshot {
            try PlaceOutingProgress.validate(snapshot)
            guard snapshot.runId == value.runID, snapshot.releaseId == value.releaseID,
                  snapshot.placeId == value.place.id else { throw PlaceOutingProgress.ProgressError.invalidContent }
        }
        return value
    }
    func save(namespace: String, defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.key(namespace: namespace))
    }
    var needsContinuation: Bool {
        cancelled != true && (snapshot.map { ![.completed, .abandoned].contains($0.status) || !pending.isEmpty } ?? true)
    }
}
