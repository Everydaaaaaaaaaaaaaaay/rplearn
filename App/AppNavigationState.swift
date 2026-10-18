import Foundation
import HomeFeature

enum AppTab: Hashable {
    case messages
    case contacts
    case home
    case me
}

enum MeDestination: Hashable {
    case favorites
    case settings
    case photoCredits
    case memory
    case account
    case subscription
    #if DEBUG
    case learningTrial
    #endif
}

extension HomeDestination {
    var navigationTitle: String {
        switch self {
        case .map: ""
        case .stories: "剧情"
        case .mainline: "主线剧情"
        case .cityStories: "城市剧情"
        case .activities: "城市活动"
        }
    }
}
