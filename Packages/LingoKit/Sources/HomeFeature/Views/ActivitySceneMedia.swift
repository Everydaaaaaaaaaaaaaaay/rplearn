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
                size: CGSize(width: 650, height: 520),
                window: .init(topLeft: .init(x: 95, y: 295), topRight: .init(x: 748, y: 295),
                    bottomRight: .init(x: 722, y: 817), bottomLeft: .init(x: 108, y: 813)),
                occluders: [[.init(x: 119, y: 795), .init(x: 355, y: 793),
                             .init(x: 379, y: 1111), .init(x: 139, y: 1157)]])
        case .bookstall:
            ActivitySceneMedia(plate: "activity-bookstall-window", video: "activity-bookstall-street-loop",
                size: CGSize(width: 512, height: 706),
                window: .init(topLeft: .zero, topRight: .init(x: 852, y: 0),
                    bottomRight: .init(x: 852, y: 1174.83), bottomLeft: .init(x: 0, y: 1174.83)),
                occluders: [], alphaForeground: true)
        case .flowerstall:
            ActivitySceneMedia(plate: "activity-flowerstall-window", video: "activity-flowerstall-street-loop",
                size: CGSize(width: 512, height: 738),
                window: .init(topLeft: .zero, topRight: .init(x: 852, y: 0),
                    bottomRight: .init(x: 852, y: 1228.13), bottomLeft: .init(x: 0, y: 1228.13)),
                occluders: [], alphaForeground: true)
        }
    }
}
