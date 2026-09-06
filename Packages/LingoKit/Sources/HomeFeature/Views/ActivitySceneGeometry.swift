import SwiftUI

enum ActivitySceneLayout {
    /// Crop the whole photograph, never move a hotspot independently of its object.
    /// Short phones need the foreground higher to clear the overlaid tab bar.
    static func origin(viewport: CGSize, canvas: CGSize) -> CGPoint {
        let ratio = viewport.height / max(viewport.width, 1)
        let compact = min(max((2.1 - ratio) / 0.25, 0), 1)
        return CGPoint(x: (viewport.width - canvas.width) / 2,
                       y: (viewport.height - canvas.height) * (0.5 + 0.5 * compact))
    }
}

/// Usable object surfaces in the original 852 × 1847 photograph, not screen pixels.
/// Map folds are not one perfect plane; use the central readable patch. The cup
/// uses its front-facing area, not the horizontal tabletop plane.
enum ActivitySceneAnchor: CaseIterable {
    case map, cup, journal, binoculars, sketchbook, postcard, cafeMenu, cafeCup, cafeBook
    case bookstallBook, bookstallRecommendations, bookstallOpenBook, flowerstallBucket, flowerstallBouquet, flowerstallTable

    var quad: HomePerspectiveQuad {
        switch self {
        case .bookstallBook:
            HomePerspectiveQuad(topLeft: CGPoint(x: 149, y: 1085), topRight: CGPoint(x: 312, y: 1126),
                                bottomRight: CGPoint(x: 214, y: 1235), bottomLeft: CGPoint(x: 54, y: 1193))
        case .bookstallRecommendations:
            HomePerspectiveQuad(topLeft: CGPoint(x: 635, y: 984), topRight: CGPoint(x: 787, y: 1035),
                                bottomRight: CGPoint(x: 673, y: 1095), bottomLeft: CGPoint(x: 523, y: 1042))
        case .bookstallOpenBook:
            HomePerspectiveQuad(topLeft: CGPoint(x: 232, y: 1425), topRight: CGPoint(x: 418, y: 1405),
                                bottomRight: CGPoint(x: 413, y: 1575), bottomLeft: CGPoint(x: 199, y: 1573))
        case .flowerstallBucket:
            HomePerspectiveQuad(topLeft: CGPoint(x: 65, y: 1170), topRight: CGPoint(x: 280, y: 1180),
                                bottomRight: CGPoint(x: 269, y: 1325), bottomLeft: CGPoint(x: 79, y: 1315))
        case .flowerstallBouquet:
            HomePerspectiveQuad(topLeft: CGPoint(x: 541, y: 1270), topRight: CGPoint(x: 723, y: 1350),
                                bottomRight: CGPoint(x: 604, y: 1480), bottomLeft: CGPoint(x: 473, y: 1405))
        case .flowerstallTable:
            // Clear worktop between the bucket and wrapping station: never
            // project one flat label across raised scissors and twine.
            HomePerspectiveQuad(topLeft: CGPoint(x: 331, y: 1290), topRight: CGPoint(x: 491, y: 1290),
                                bottomRight: CGPoint(x: 499, y: 1380), bottomLeft: CGPoint(x: 319, y: 1380))
        case .cafeMenu:
            HomePerspectiveQuad(topLeft: CGPoint(x: 155, y: 905), topRight: CGPoint(x: 341, y: 898),
                                bottomRight: CGPoint(x: 351, y: 1040), bottomLeft: CGPoint(x: 162, y: 1051))
        case .cafeCup:
            HomePerspectiveQuad(topLeft: CGPoint(x: 552, y: 1088), topRight: CGPoint(x: 703, y: 1100),
                                bottomRight: CGPoint(x: 690, y: 1200), bottomLeft: CGPoint(x: 556, y: 1188))
        case .cafeBook:
            HomePerspectiveQuad(topLeft: CGPoint(x: 182, y: 1295), topRight: CGPoint(x: 319, y: 1250),
                                bottomRight: CGPoint(x: 465, y: 1360), bottomLeft: CGPoint(x: 307, y: 1440))
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
