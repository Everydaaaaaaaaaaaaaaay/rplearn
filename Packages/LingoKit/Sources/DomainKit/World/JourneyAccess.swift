/// 身份决定旅行和剧情范围；订阅等级不改变游客身份。
public struct JourneyAccess: Sendable {
    public let isGuest: Bool
    public let requestSignIn: @MainActor @Sendable (String) -> Void

    public init(isGuest: Bool = false, requestSignIn: @escaping @MainActor @Sendable (String) -> Void = { _ in }) {
        self.isGuest = isGuest
        self.requestSignIn = requestSignIn
    }

    public func allowsStory(_ storyID: String, starterRegionID: String?) -> Bool {
        guard isGuest else { return true }
        let journey = MainlineCatalog.journey(starterRegionID: starterRegionID)
        let first = journey.stops.first?.chapter.storyID
        let cityFirst = CityStoryCatalog.chapters.first { $0.regionID == journey.starterRegionID }?.storyID
        return storyID == first || storyID == cityFirst
    }
}
