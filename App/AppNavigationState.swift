import Foundation

enum AppTab: Hashable {
    case messages
    case contacts
    case home
    case me
    #if DEBUG
    case relationshipLab
    #endif
}

enum MeDestination: Hashable {
    case favorites
    case settings
    case photoCredits
    #if DEBUG
    case memory
    #endif

    var navigationTitle: String {
        switch self {
        case .favorites:
            "收藏夹"
        case .settings:
            "设置"
        case .photoCredits:
            "城市背景照片"
        #if DEBUG
        case .memory:
            ""
        #endif
        }
    }
}
