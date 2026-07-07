import Foundation

/// 地区静态数据（regions.json），不建实体。
public struct Region: Sendable, Codable, Equatable, Identifiable {
    public struct Activity: Sendable, Codable, Equatable, Identifiable {
        public var id: String
        public var titleZh: String
        public var detailZh: String
    }

    public var id: String
    public var nameEn: String
    public var nameZh: String
    public var countryCode: String
    public var countryNameEn: String
    public var countryNameZh: String
    public var taglineZh: String
    public var landmarks: [String]
    public var activities: [Activity]
}

public struct RegionCatalog: Sendable {
    public let regions: [Region]
    private let regionsByID: [String: Region]

    public init(url: URL) throws {
        struct File: Decodable {
            let regions: [Region]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(File.self, from: Data(contentsOf: url))
        self.init(regions: file.regions)
    }

    public init(regions: [Region]) {
        self.regions = regions
        self.regionsByID = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })
    }

    public func region(id: String) -> Region? {
        regionsByID[id]
    }
}
