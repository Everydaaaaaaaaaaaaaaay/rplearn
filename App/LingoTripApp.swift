import SwiftUI

@main
struct LingoTripApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
    }
}
