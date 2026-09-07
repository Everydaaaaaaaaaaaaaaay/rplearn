import DomainKit
import PersistenceKit

/// 把仍持有的机票与已经消费后留下的永久凭据合并成城市剧情解锁进度。
/// 旧版本可能只有地区到访记录而没有票根，因此以两种已消费证据中的较大值兜底。
struct CityStoryUnlockProgress: Equatable, Sendable {
    let earnedTicketCount: Int

    var unlockedChapterCount: Int {
        CityStoryCatalog.unlockedChapterCount(earnedTicketCount: earnedTicketCount)
    }

    init(
        profile: UserProfileDTO?,
        availableTickets: [ItemDTO],
        ticketStubs: [TicketStubDTO]
    ) {
        let visitedSideRegionCount: Int
        if let profile {
            let visited = Set(profile.unlockedRegionIDs + [profile.currentRegionID])
            visitedSideRegionCount = visited
                .subtracting(MainlineCatalog.defaultUnlockedRegionIDs)
                .count
        } else {
            visitedSideRegionCount = 0
        }
        let consumedTicketCount = max(ticketStubs.count, visitedSideRegionCount)
        earnedTicketCount = availableTickets.count + consumedTicketCount
    }
}
