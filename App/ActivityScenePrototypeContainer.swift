import DomainKit
import HomeFeature
import PersistenceKit
import SwiftUI

/// Keep the pilot opt-in until visual acceptance. Reuse App's actual photographic
/// navigation container, including its crossfade and leading-edge return gesture.
struct ActivityScenePrototypeContainer: View {
    let deps: HomeDependencies
    let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    @State private var category: Region.ActivityCategory?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SceneNavigationContainer(isPresentingDestination: category != nil,
                                 navigationTitle: "城市活动", onBack: { category = nil }) {
            ActivitySceneView(isVisible: category == nil, onClose: { dismiss() }, onSelect: { category = $0 })
        } destination: {
            ActivitiesView(deps: deps, chatBuilder: chatBuilder, initialCategory: category)
        }
    }
}
