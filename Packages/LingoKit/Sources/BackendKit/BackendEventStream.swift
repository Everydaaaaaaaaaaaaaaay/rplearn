import Foundation

public struct BackendServerSentEvent: Sendable, Equatable {
    public let data: String
    public let name: String?

    public init(name: String?, data: String) {
        self.name = name
        self.data = data
    }
}
