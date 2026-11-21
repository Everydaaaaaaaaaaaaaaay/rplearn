import SwiftUI

/// Shared cross-dissolve for tabs and photographic scene transitions.
public enum DSSceneTransition {
    public static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.09 : 0.15
    }

    public static func animation(reduceMotion: Bool) -> Animation {
        .easeOut(duration: duration(reduceMotion: reduceMotion))
    }
}
