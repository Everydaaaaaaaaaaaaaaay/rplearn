import DesignSystem
import SwiftUI

@main
struct LingoTripApp: App {
    @State private var environment = AppEnvironment()

    init() {
        DSTypography.configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .fontDesign(.rounded)
                .tint(.dsSky)
        }
    }
}
