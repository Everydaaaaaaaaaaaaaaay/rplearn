/// Reading IDs version new narratives; reward IDs preserve the existing ledger.
public enum DepartureStoryIdentity {
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

    public static func rewardID(for storyID: String) -> String? { rewardIDs[storyID] }
}
