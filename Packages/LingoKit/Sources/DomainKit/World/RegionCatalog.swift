import Foundation

public enum RegionRole: String, Sendable, Codable, Equatable {
    case mainline
    case side
}

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
    public var role: RegionRole
    public var taglineZh: String
    public var landmarks: [String]
    public var activities: [Activity]
    public var latitude: Double
    public var longitude: Double

    public init(
        id: String,
        nameEn: String,
        nameZh: String,
        countryCode: String,
        countryNameEn: String,
        countryNameZh: String,
        role: RegionRole = .side,
        taglineZh: String,
        landmarks: [String],
        activities: [Activity],
        latitude: Double = 0,
        longitude: Double = 0
    ) {
        self.id = id
        self.nameEn = nameEn
        self.nameZh = nameZh
        self.countryCode = countryCode
        self.countryNameEn = countryNameEn
        self.countryNameZh = countryNameZh
        self.role = role
        self.taglineZh = taglineZh
        self.landmarks = landmarks
        self.activities = activities
        self.latitude = latitude
        self.longitude = longitude
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case nameEn
        case nameZh
        case countryCode
        case countryNameEn
        case countryNameZh
        case role
        case taglineZh
        case landmarks
        case activities
        case latitude
        case longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        nameEn = try container.decode(String.self, forKey: .nameEn)
        nameZh = try container.decode(String.self, forKey: .nameZh)
        countryCode = try container.decode(String.self, forKey: .countryCode)
        countryNameEn = try container.decode(String.self, forKey: .countryNameEn)
        countryNameZh = try container.decode(String.self, forKey: .countryNameZh)
        role = try container.decodeIfPresent(RegionRole.self, forKey: .role) ?? .side
        taglineZh = try container.decode(String.self, forKey: .taglineZh)
        landmarks = try container.decode([String].self, forKey: .landmarks)
        activities = try container.decode([Activity].self, forKey: .activities)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
    }
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

    public var mainlineRegions: [Region] {
        regions.filter { $0.role == .mainline }
    }

    public var sideRegions: [Region] {
        regions.filter { $0.role == .side }
    }
}
