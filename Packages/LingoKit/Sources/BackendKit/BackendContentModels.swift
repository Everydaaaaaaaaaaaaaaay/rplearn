import Foundation

public enum BackendJSONValue: Codable, Sendable, Equatable {
    case array([BackendJSONValue])
    case boolean(Bool)
    case null
    case number(Double)
    case object([String: BackendJSONValue])
    case string(String)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let boolean = try? value.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let array = try? value.decode([BackendJSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try value.decode([String: BackendJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .array(let array):
            try value.encode(array)
        case .boolean(let boolean):
            try value.encode(boolean)
        case .null:
            try value.encodeNil()
        case .number(let number):
            try value.encode(number)
        case .object(let object):
            try value.encode(object)
        case .string(let string):
            try value.encode(string)
        }
    }

    public static func decode(json: String) throws -> BackendJSONValue {
        try JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }

    public func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

public struct BackendContentRecord: Codable, Sendable, Equatable {
    public let createdAt: String
    public let deletedAt: String?
    public let parentId: String?
    public let payload: BackendJSONValue
    public let resourceId: String
    public let resourceType: String
    public let updatedAt: String
    public let version: Int

    public static func decode(_ value: BackendJSONValue) throws -> Self {
        let encoder = JSONEncoder()
        return try JSONDecoder().decode(Self.self, from: encoder.encode(value))
    }
}

public struct BackendContentPage: Decodable, Sendable, Equatable {
    public let hasMore: Bool
    public let nextCursor: String?
    public let records: [BackendContentRecord]
    public let syncCursor: String
}

public struct BackendContentCommand: Encodable, Sendable, Equatable {
    public let commandId: UUID
    public let expectedVersion: Int
    public let operation: String
    public let parentId: String?
    public let payload: BackendJSONValue?
    public let resourceId: String
    public let resourceType: String

    public init(
        commandID: UUID,
        expectedVersion: Int,
        operation: String,
        parentID: String?,
        payload: BackendJSONValue?,
        resourceID: String,
        resourceType: String
    ) {
        self.commandId = commandID
        self.expectedVersion = expectedVersion
        self.operation = operation
        self.parentId = parentID
        self.payload = payload
        self.resourceId = resourceID
        self.resourceType = resourceType
    }
}

public struct BackendContentCommandError: Decodable, Sendable, Equatable {
    public let code: String
    public let details: BackendJSONValue?
    public let message: String
}

public struct BackendContentCommandResult: Decodable, Sendable, Equatable {
    public let commandId: UUID
    public let error: BackendContentCommandError?
    public let record: BackendContentRecord?
    public let status: String
}

private struct BackendContentCommandBatch: Encodable, Sendable {
    let commands: [BackendContentCommand]
}

private struct BackendContentCommandBatchResponse: Decodable, Sendable {
    let results: [BackendContentCommandResult]
}

extension BackendClient {
    public func contentPage(
        cursor: String?,
        limit: Int = 200
    ) async throws -> BackendContentPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await get("/v1/content/records", queryItems: query)
    }

    public func submitContentCommands(
        _ commands: [BackendContentCommand]
    ) async throws -> [BackendContentCommandResult] {
        let response: BackendContentCommandBatchResponse = try await send(
            path: "/v1/content/commands",
            method: "POST",
            body: BackendContentCommandBatch(commands: commands)
        )
        return response.results
    }
}
