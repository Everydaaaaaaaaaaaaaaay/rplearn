import SwiftUI

/// Receiving surfaces in the immutable 852 × 1847 photo. Only light moves;
/// there is no second camera, video aperture or moving photograph.
struct ActivitySceneMedia {
    let lightPlanes: [HomePerspectiveQuad]
    let seed: UInt64
}

extension ActivitySceneID {
    var media: ActivitySceneMedia {
        switch self {
        case .cafe:
            ActivitySceneMedia(lightPlanes: [
                .init(topLeft: .init(x: 565, y: 798), topRight: .init(x: 839, y: 748),
                      bottomRight: .init(x: 845, y: 1020), bottomLeft: .init(x: 500, y: 960)),
                // Empty tabletop, excluding cup, saucer and pastry.
                .init(topLeft: .init(x: 75, y: 1530), topRight: .init(x: 780, y: 1490),
                      bottomRight: .init(x: 790, y: 1585), bottomLeft: .init(x: 170, y: 1690))
            ], seed: 41)
        case .bookstall:
            ActivitySceneMedia(lightPlanes: [
                // Continuous paving between the tables; never warp books.
                .init(topLeft: .init(x: 320, y: 735), topRight: .init(x: 740, y: 690),
                      bottomRight: .init(x: 740, y: 882), bottomLeft: .init(x: 180, y: 882))
            ], seed: 73)
        case .flowerstall:
            ActivitySceneMedia(lightPlanes: [
                // Pedestrian apron, clear of the bucket and flower stems.
                .init(topLeft: .init(x: 490, y: 800), topRight: .init(x: 820, y: 790),
                      bottomRight: .init(x: 820, y: 1000), bottomLeft: .init(x: 305, y: 1028))
            ], seed: 109)
        }
    }
}
