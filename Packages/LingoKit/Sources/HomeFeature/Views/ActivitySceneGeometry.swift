import SwiftUI

/// Usable object surfaces in the original 852 × 1847 photograph, not screen pixels.
/// Map folds are not one perfect plane; use the central readable patch. The cup
/// uses its front-facing area, not the horizontal tabletop plane.
enum ActivitySceneAnchor: CaseIterable {
    case map, cup, journal, binoculars, sketchbook, postcard

    var quad: HomePerspectiveQuad {
        switch self {
        case .map:
            HomePerspectiveQuad(topLeft: CGPoint(x: 22, y: 1280), topRight: CGPoint(x: 353, y: 1198),
                                bottomRight: CGPoint(x: 484, y: 1401), bottomLeft: CGPoint(x: 113, y: 1498))
        case .cup:
            HomePerspectiveQuad(topLeft: CGPoint(x: 567, y: 1158), topRight: CGPoint(x: 756, y: 1158),
                                bottomRight: CGPoint(x: 790, y: 1286), bottomLeft: CGPoint(x: 552, y: 1286))
        case .journal:
            HomePerspectiveQuad(topLeft: CGPoint(x: 529, y: 1397), topRight: CGPoint(x: 772, y: 1451),
                                bottomRight: CGPoint(x: 707, y: 1647), bottomLeft: CGPoint(x: 450, y: 1575))
        case .binoculars:
            HomePerspectiveQuad(topLeft: CGPoint(x: 599, y: 906), topRight: CGPoint(x: 792, y: 953),
                                bottomRight: CGPoint(x: 754, y: 1082), bottomLeft: CGPoint(x: 552, y: 1024))
        case .sketchbook:
            HomePerspectiveQuad(topLeft: CGPoint(x: 97, y: 1118), topRight: CGPoint(x: 418, y: 1051),
                                bottomRight: CGPoint(x: 477, y: 1252), bottomLeft: CGPoint(x: 124, y: 1338))
        case .postcard:
            HomePerspectiveQuad(topLeft: CGPoint(x: 531, y: 1400), topRight: CGPoint(x: 762, y: 1380),
                                bottomRight: CGPoint(x: 784, y: 1512), bottomLeft: CGPoint(x: 540, y: 1537))
        }
    }

    var bounds: CGRect {
        let xs = quad.points.map(\.x), ys = quad.points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    func localQuad(scale: CGFloat) -> HomePerspectiveQuad {
        func local(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - bounds.minX) * scale, y: (p.y - bounds.minY) * scale)
        }
        return HomePerspectiveQuad(topLeft: local(quad.topLeft), topRight: local(quad.topRight),
                                   bottomRight: local(quad.bottomRight), bottomLeft: local(quad.bottomLeft))
    }
}

/// Same homography as Home's Metal path, applied by Core Animation to the shared
/// SwiftUI material. Icon, text and contact shadows go through ONE projection.
struct ActivityPlaneProjection: GeometryEffect {
    let quad: HomePerspectiveQuad

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard size.width > 0, size.height > 0 else { return ProjectionTransform(CATransform3DIdentity) }
        let h = HomeHomography(quad: quad)
        var matrix = CATransform3DIdentity
        matrix.m11 = h.a / size.width
        matrix.m12 = h.d / size.width
        matrix.m14 = h.g / size.width
        matrix.m21 = h.b / size.height
        matrix.m22 = h.e / size.height
        matrix.m24 = h.h / size.height
        matrix.m41 = h.c
        matrix.m42 = h.f
        matrix.m44 = h.i
        return ProjectionTransform(matrix)
    }
}

/// Repetition is sparse, bounded and deliberately non-periodic. A quarter of
/// draws use a longer quiet interval; normal motion is never time-stretched.
struct ActivityAmbientCadence {
    private(set) var previousDelay: TimeInterval?

    mutating func nextDelay(using generator: inout some RandomNumberGenerator) -> TimeInterval {
        let longPause = Int.random(in: 0..<4, using: &generator) == 0
        var delay = Double.random(in: longPause ? 65...95 : 24...62, using: &generator)
        if let previousDelay, abs(delay - previousDelay) < 8 {
            delay = previousDelay > 60 ? previousDelay - 16 : previousDelay + 16
        }
        previousDelay = delay
        return delay
    }
}
