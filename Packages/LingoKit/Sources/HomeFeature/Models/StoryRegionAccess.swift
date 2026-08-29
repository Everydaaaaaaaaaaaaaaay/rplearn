import DomainKit
import PersistenceKit

enum StoryRegionAccess: Equatable {
    case current
    case unlockedAway
    case locked

    init(regionID: String, profile: UserProfileDTO) {
        if profile.currentRegionID == regionID {
            self = .current
        } else if MainlineCatalog.defaultUnlockedRegionIDs.contains(regionID)
            || profile.unlockedRegionIDs.contains(regionID)
        {
            self = .unlockedAway
        } else {
            self = .locked
        }
    }

    var canOpen: Bool {
        self != .locked
    }
}

func storyTravelErrorMessage(_ error: Error) -> String {
    switch error as? TravelService.TravelError {
    case .ticketRequired:
        "这座城市尚未解锁，请先在地图使用机票完成首次抵达。"
    case .ticketNotUsable:
        "当前机票不能用于这座城市，请前往地图重新选择。"
    case .alreadyThere:
        "位置已经切换完成，请再试一次。"
    case nil:
        "位置同步暂时没有完成，请检查网络后重试。"
    }
}
