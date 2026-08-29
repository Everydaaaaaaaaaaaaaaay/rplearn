enum CityPinState: Equatable, Sendable {
    case current
    case unlocked
    case locked

    var accessibilityText: String {
        switch self {
        case .current: "当前城市"
        case .unlocked: "已解锁"
        case .locked: "未解锁"
        }
    }
}

struct MapRegionPresentation: Equatable, Sendable {
    let state: CityPinState
    let hasUsableTicket: Bool
}
