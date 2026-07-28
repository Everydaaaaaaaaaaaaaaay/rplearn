import Foundation

public enum RegionRole: String, Sendable, Codable, Equatable {
    case mainline
    case side
}

/// 地区静态数据（regions.json），不建实体。
public struct Region: Sendable, Codable, Equatable, Identifiable {
    public enum ActivityCategory: String, Sendable, Codable, Equatable, CaseIterable {
        case culture
        case food
        case outdoors
        case social
        case night
    }

    public struct Activity: Sendable, Codable, Equatable, Identifiable {
        public var id: String
        public var titleZh: String
        public var detailZh: String
        public var category: ActivityCategory
        public var durationMinutes: Int
        public var encounterProbability: Double
        public var outcomeZh: String

        public init(
            id: String,
            titleZh: String,
            detailZh: String,
            category: ActivityCategory = .culture,
            durationMinutes: Int = 30,
            encounterProbability: Double = 0.35,
            outcomeZh: String = "你放慢脚步，记住了这座城市此刻的声音与光线。"
        ) {
            self.id = id
            self.titleZh = titleZh
            self.detailZh = detailZh
            self.category = category
            self.durationMinutes = max(5, durationMinutes)
            self.encounterProbability = min(max(encounterProbability, 0), 1)
            self.outcomeZh = outcomeZh
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case titleZh
            case detailZh
            case category
            case durationMinutes
            case encounterProbability
            case outcomeZh
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            titleZh = try container.decode(String.self, forKey: .titleZh)
            detailZh = try container.decode(String.self, forKey: .detailZh)
            category = try container.decodeIfPresent(
                ActivityCategory.self,
                forKey: .category
            ) ?? .culture
            durationMinutes = max(
                5,
                try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 30
            )
            encounterProbability = min(
                max(
                    try container.decodeIfPresent(
                        Double.self,
                        forKey: .encounterProbability
                    ) ?? 0.35,
                    0
                ),
                1
            )
            outcomeZh = try container.decodeIfPresent(
                String.self,
                forKey: .outcomeZh
            ) ?? "你放慢脚步，记住了这座城市此刻的声音与光线。"
        }
    }

    public var id: String
    public var nameEn: String
    public var nameZh: String
    public var countryCode: String
    public var countryNameEn: String
    public var countryNameZh: String
    public var learningLanguageCode: String
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
        learningLanguageCode: String = "en",
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
        self.learningLanguageCode = learningLanguageCode
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
        case learningLanguageCode
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
        learningLanguageCode = try container.decode(
            String.self,
            forKey: .learningLanguageCode
        )
        role = try container.decodeIfPresent(RegionRole.self, forKey: .role) ?? .side
        taglineZh = try container.decode(String.self, forKey: .taglineZh)
        landmarks = try container.decode([String].self, forKey: .landmarks)
        activities = try container.decode([Activity].self, forKey: .activities)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
    }
}

public struct RegionCatalog: Sendable {
    public static let supportedLearningLanguageCode = "en"

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
        let supportedRegions = regions.filter {
            $0.learningLanguageCode == Self.supportedLearningLanguageCode
        }
        self.regions = supportedRegions
        self.regionsByID = Dictionary(
            uniqueKeysWithValues: supportedRegions.map { ($0.id, $0) }
        )
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
