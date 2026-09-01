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
}
