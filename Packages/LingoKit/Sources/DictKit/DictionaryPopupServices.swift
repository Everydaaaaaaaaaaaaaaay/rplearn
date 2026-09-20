import SwiftUI

/// App composition supplies this once above every presentation boundary.
/// Individual screens cannot replace example translation or disable its fallback.
public struct DictionaryPopupServices: Sendable {
    let examples: DictExampleTranslationActions

    public init(examples: DictExampleTranslationActions) {
        self.examples = examples
    }
}

private struct DictionaryPopupServicesKey: EnvironmentKey {
    static let defaultValue: DictionaryPopupServices? = nil
}

extension EnvironmentValues {
    var dictionaryPopupServices: DictionaryPopupServices? {
        get { self[DictionaryPopupServicesKey.self] }
        set { self[DictionaryPopupServicesKey.self] = newValue }
    }
}

extension View {
    /// Install at the App root, outside sheets/covers. Never install per feature.
    public func dictionaryPopupServices(_ services: DictionaryPopupServices) -> some View {
        environment(\.dictionaryPopupServices, services)
    }
}
