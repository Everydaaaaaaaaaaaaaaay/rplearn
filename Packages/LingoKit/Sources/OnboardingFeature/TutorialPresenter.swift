import PersistenceKit
import SwiftUI

/// App composes the actual feature screens; Onboarding never imports sibling features.
public typealias TutorialPresenter = @MainActor @Sendable (
    CharacterDTO, @escaping @MainActor () async -> Bool
) -> AnyView
