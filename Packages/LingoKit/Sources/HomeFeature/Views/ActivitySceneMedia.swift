import CoreGraphics
import Foundation

enum ActivityScenePlaybackMode: Equatable, Sendable {
    case sparseEvent
    case seamlessLoop
}

/// All dimensions share the immutable 852 × 1847 scene canvas.
/// A foreground is optional because the rain cafe already contains its table
/// and window in one locked-off real take.
struct ActivitySceneMedia: Equatable, Sendable {
    let poster: String
    let video: String
    let foreground: String?
    let videoHeight: CGFloat
    let foregroundTop: CGFloat?
    let playbackMode: ActivityScenePlaybackMode
    let expectedDuration: TimeInterval
}

extension ActivitySceneID {
    var media: ActivitySceneMedia {
        switch self {
        case .park:
            ActivitySceneMedia(
                poster: "activity-park-poster",
                video: "activity-park-loop",
                foreground: "activity-table",
                videoHeight: 1108,
                foregroundTop: 1058,
                playbackMode: .sparseEvent,
                expectedDuration: 8
            )
        case .pond:
            ActivitySceneMedia(
                poster: "activity-pond-poster",
                video: "activity-pond-loop",
                foreground: "activity-pond-table",
                videoHeight: 852,
                foregroundTop: 848,
                playbackMode: .seamlessLoop,
                expectedDuration: 18
            )
        case .raincafe:
            ActivitySceneMedia(
                poster: "activity-raincafe-poster",
                video: "activity-raincafe-loop",
                foreground: nil,
                videoHeight: 1847,
                foregroundTop: nil,
                playbackMode: .seamlessLoop,
                expectedDuration: 17.5
            )
        }
    }
}
