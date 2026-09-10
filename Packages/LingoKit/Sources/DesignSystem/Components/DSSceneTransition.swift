import SwiftUI

/// Shared cross-dissolve for Home, My and photographic scene activities.
public enum DSSceneTransition {
    public static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.10 : 0.18
    }

    public static func animation(reduceMotion: Bool) -> Animation {
        let duration = duration(reduceMotion: reduceMotion)
        return reduceMotion ? .easeOut(duration: duration) : .easeInOut(duration: duration)
    }
}
