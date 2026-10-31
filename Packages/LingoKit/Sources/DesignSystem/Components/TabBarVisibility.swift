import SwiftUI

public extension View {
    func dsTabBarHidden(_ hidden: Bool = true) -> some View {
        toolbar(hidden ? .hidden : .automatic, for: .tabBar)
            .preference(key: DSTabBarHiddenPreference.self, value: hidden)
    }
}
