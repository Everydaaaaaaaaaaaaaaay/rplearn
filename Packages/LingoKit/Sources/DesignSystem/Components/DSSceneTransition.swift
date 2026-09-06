import SwiftUI

/// Shared cross-dissolve for Home, My and photographic scene activities.
public enum DSSceneTransition {
    public static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.10) : .easeInOut(duration: 0.18)
    }
}
