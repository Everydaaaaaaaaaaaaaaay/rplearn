/// Reading IDs version new narratives; reward IDs preserve the existing ledger.
public enum DepartureStoryIdentity {
    /// Catalog IDs remain stable; each rewritten edition owns its reading progress.
    public static let currentEditions: [String: String] = [
        "departures_mainline_melbourne_v1": "departures_mainline_melbourne_v3",
        "departures_city_newyork_v1": "departures_city_newyork_v3",
        "departures_mainline_singapore_v1": "departures_mainline_singapore_v3",
        "departures_city_toronto_v1": "departures_city_toronto_v3",
        "departures_city_auckland_v1": "departures_city_auckland_v3",
        "departures_london_v1": "departures_london_v2",
        "departures_mainline_newyork_v1": "departures_mainline_newyork_v2",
        "departures_mainline_capetown_v1": "departures_mainline_capetown_v2",
        "departures_city_london_v1": "departures_city_london_v2",
        "departures_city_melbourne_v1": "departures_city_melbourne_v2",
        "departures_city_capetown_v1": "departures_city_capetown_v2",
        "departures_city_singapore_v1": "departures_city_singapore_v2",
        "departures_city_dublin_v1": "departures_city_dublin_v2",
        "departures_city_edinburgh_v1": "departures_city_edinburgh_v2",
        "departures_city_vancouver_v1": "departures_city_vancouver_v2",
        "departures_city_nairobi_v1": "departures_city_nairobi_v2",
        "departures_city_sydney_v1": "departures_city_sydney_v2",
        "departures_city_neworleans_v1": "departures_city_neworleans_v2",
        "departures_city_manchester_v1": "departures_city_manchester_v2",
        "departures_city_kingston_v1": "departures_city_kingston_v2",
    ]

    /// Intermediate editions retain their progress, completions and rewards.
    public static let previousEditions: [String: [String]] = [
        "departures_mainline_melbourne_v1": ["departures_mainline_melbourne_v2"],
        "departures_city_newyork_v1": ["departures_city_newyork_v2"],
        "departures_mainline_singapore_v1": ["departures_mainline_singapore_v2"],
        "departures_city_toronto_v1": ["departures_city_toronto_v2"],
        "departures_city_auckland_v1": ["departures_city_auckland_v2"],
    ]

    public static func catalogID(for readingID: String) -> String {
        currentEditions.first { $0.value == readingID }?.key
            ?? previousEditions.first { $0.value.contains(readingID) }?.key
            ?? readingID
    }

    /// Ordered oldest to newest, including the stable original resource.
    public static func readingEditions(for storyID: String) -> [String] {
        let original = catalogID(for: storyID)
        return [original] + (previousEditions[original] ?? [])
            + (currentEditions[original].map { [$0] } ?? [])
    }

    public static func catalogCompletionIDs(_ readingIDs: Set<String>) -> Set<String> {
        readingIDs.union(readingIDs.map { catalogID(for: $0) })
    }

    /// Prefer a started current edition, otherwise resume the newest unfinished
    /// older edition. Completed older stories remain available in reading history.
    public static func readingID(for requestedID: String, unfinishedEditions: Set<String>,
                                 startedEditions: Set<String>) -> String {
        let editions = readingEditions(for: requestedID)
        let current = editions.last ?? requestedID
        if startedEditions.contains(current) { return current }
        return editions.reversed().first { unfinishedEditions.contains($0) } ?? current
    }

    public static func readingID(for requestedID: String, hasUnfinishedOriginal: Bool,
                                 hasCurrentProgress: Bool = false) -> String {
        readingID(for: requestedID,
                  unfinishedEditions: hasUnfinishedOriginal ? [requestedID] : [],
                  startedEditions: hasCurrentProgress ? [currentEditions[requestedID] ?? requestedID] : [])
    }

    public static let rewardIDs: [String: String] = [
        "departures_london_v1": "mainline_london",
        "departures_mainline_melbourne_v1": "mainline_melbourne",
        "departures_mainline_newyork_v1": "mainline_newyork",
        "departures_mainline_capetown_v1": "mainline_capetown",
        "departures_mainline_singapore_v1": "mainline_singapore",
        "departures_city_london_v1": "mainline_london_2",
        "departures_city_melbourne_v1": "mainline_melbourne_2",
        "departures_city_newyork_v1": "mainline_newyork_2",
        "departures_city_capetown_v1": "city_capetown",
        "departures_city_singapore_v1": "city_singapore",
        "departures_city_dublin_v1": "city_dublin",
        "departures_city_edinburgh_v1": "city_edinburgh",
        "departures_city_vancouver_v1": "city_vancouver",
        "departures_city_auckland_v1": "city_auckland",
        "departures_city_nairobi_v1": "city_nairobi",
        "departures_city_toronto_v1": "city_toronto",
        "departures_city_sydney_v1": "city_sydney",
        "departures_city_neworleans_v1": "city_neworleans",
        "departures_city_manchester_v1": "city_manchester",
        "departures_city_kingston_v1": "city_kingston",
    ]

    public static func rewardID(for storyID: String) -> String? { rewardIDs[catalogID(for: storyID)] }
}
