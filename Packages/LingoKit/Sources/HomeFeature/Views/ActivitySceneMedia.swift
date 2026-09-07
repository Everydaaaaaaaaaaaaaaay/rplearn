import SwiftUI

/// All locations are in the immutable 852 × 1847 master, not safe-area coordinates.
/// A scene owns its own plate, aperture and foreground occlusion; shared render
/// materials and interactions stay identical.
struct ActivitySceneMedia {
    let plate: String
    let video: String
    let size: CGSize
    let window: HomePerspectiveQuad
    let occluders: [[CGPoint]]
    var alphaForeground = false

    var origin: CGPoint { window.topLeft }
    func localWindow(scale: CGFloat) -> HomePerspectiveQuad {
        func local(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - origin.x) * scale, y: (p.y - origin.y) * scale)
        }
        return HomePerspectiveQuad(topLeft: .zero, topRight: local(window.topRight),
            bottomRight: local(window.bottomRight), bottomLeft: local(window.bottomLeft))
    }
}

extension ActivitySceneID {
    var media: ActivitySceneMedia {
        switch self {
        case .cafe:
            ActivitySceneMedia(plate: "activity-cafe-window", video: "activity-cafe-street-loop",
                size: CGSize(width: 650, height: 404),
                window: .init(topLeft: .init(x: 82, y: 340), topRight: .init(x: 827, y: 340),
                    bottomRight: .init(x: 822, y: 803), bottomLeft: .init(x: 84, y: 803)),
                occluders: [])
        case .bookstall:
            ActivitySceneMedia(plate: "activity-bookstall-window", video: "activity-bookstall-street-loop",
                size: CGSize(width: 1024, height: 1412),
                window: .init(topLeft: .zero, topRight: .init(x: 852, y: 0),
                    bottomRight: .init(x: 852, y: 1174.83), bottomLeft: .init(x: 0, y: 1174.83)),
                occluders: [], alphaForeground: true)
        case .flowerstall:
            ActivitySceneMedia(plate: "activity-flowerstall-window", video: "activity-flowerstall-street-loop",
                size: CGSize(width: 750, height: 1080),
                window: .init(topLeft: .zero, topRight: .init(x: 852, y: 0),
                    bottomRight: .init(x: 852, y: 1228.13), bottomLeft: .init(x: 0, y: 1228.13)),
                occluders: [], alphaForeground: true)
        }
    }
}
