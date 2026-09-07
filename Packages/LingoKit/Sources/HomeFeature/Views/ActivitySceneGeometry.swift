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
    case map, cup, journal, binoculars, sketchbook, postcard, cafeSill, cafeCup, cafePastry
    case bookstallBook, bookstallRecommendations, bookstallOpenBook, flowerstallBucket, flowerstallBouquet, flowerstallTable

    var quad: HomePerspectiveQuad {
        switch self {
        case .bookstallBook:
            HomePerspectiveQuad(topLeft: CGPoint(x: 140, y: 962), topRight: CGPoint(x: 300, y: 976),
                                bottomRight: CGPoint(x: 300, y: 1065), bottomLeft: CGPoint(x: 140, y: 1050))
        case .bookstallRecommendations:
            HomePerspectiveQuad(topLeft: CGPoint(x: 565, y: 979), topRight: CGPoint(x: 740, y: 1015),
                                bottomRight: CGPoint(x: 725, y: 1100), bottomLeft: CGPoint(x: 550, y: 1065))
        case .bookstallOpenBook:
            HomePerspectiveQuad(topLeft: CGPoint(x: 327, y: 1300), topRight: CGPoint(x: 517, y: 1310),
                                bottomRight: CGPoint(x: 515, y: 1430), bottomLeft: CGPoint(x: 325, y: 1420))
        case .flowerstallBucket:
            HomePerspectiveQuad(topLeft: CGPoint(x: 80, y: 994), topRight: CGPoint(x: 257, y: 994),
                                bottomRight: CGPoint(x: 254, y: 1120), bottomLeft: CGPoint(x: 85, y: 1120))
        case .flowerstallBouquet:
            HomePerspectiveQuad(topLeft: CGPoint(x: 545, y: 1280), topRight: CGPoint(x: 721, y: 1340),
                                bottomRight: CGPoint(x: 673, y: 1440), bottomLeft: CGPoint(x: 500, y: 1380))
        case .flowerstallTable:
            // Near-side wrapping space: separate the waiting action from both
            // the bucket and bouquet, including their complete touch regions.
            HomePerspectiveQuad(topLeft: CGPoint(x: 245, y: 1260), topRight: CGPoint(x: 395, y: 1260),
                                bottomRight: CGPoint(x: 395, y: 1380), bottomLeft: CGPoint(x: 245, y: 1380))
        case .cafeSill:
            // Historical enum name; v4 anchors the nearby conversation to the
            // open courtyard beyond the chair, not an imaginary window sill.
            HomePerspectiveQuad(topLeft: CGPoint(x: 463, y: 942), topRight: CGPoint(x: 643, y: 930),
                                bottomRight: CGPoint(x: 643, y: 1040), bottomLeft: CGPoint(x: 463, y: 1052))
        case .cafeCup:
            HomePerspectiveQuad(topLeft: CGPoint(x: 580, y: 1230), topRight: CGPoint(x: 750, y: 1230),
                                bottomRight: CGPoint(x: 742, y: 1340), bottomLeft: CGPoint(x: 584, y: 1340))
        case .cafePastry:
            // Empty near-side table, not glowing lettering projected over food.
            HomePerspectiveQuad(topLeft: CGPoint(x: 170, y: 1130), topRight: CGPoint(x: 355, y: 1120),
                                bottomRight: CGPoint(x: 355, y: 1230), bottomLeft: CGPoint(x: 170, y: 1240))
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

    /// The object is the anchor, not a mould into which we squeeze the glyphs.
    /// This small floating plaque keeps the object's heading but turns towards
    /// the observer. Width/height stay proportional even on a steep tabletop.
    /// Coordinates remain attached to the photograph when its crop changes.
    var entranceQuad: HomePerspectiveQuad {
        let width: CGFloat = 248
        let height = width * 100 / 128
        let edge = CGVector(dx: quad.topRight.x - quad.topLeft.x,
                            dy: quad.topRight.y - quad.topLeft.y)
        let angle = min(max(atan2(edge.dy, edge.dx), -.pi / 15), .pi / 15)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: bounds.midX + x * cos(angle) - y * sin(angle),
                    y: bounds.midY + x * sin(angle) + y * cos(angle))
        }
        // A two-percent depth taper is enough to retain a spatial plane without
        // reproducing the steep foreshortening of a tiny cup or horizontal book.
        return HomePerspectiveQuad(topLeft: point(-width * 0.49, -height / 2),
            topRight: point(width * 0.49, -height / 2),
            bottomRight: point(width / 2, height / 2),
            bottomLeft: point(-width / 2, height / 2))
    }

    var entranceBounds: CGRect {
        let points = entranceQuad.points
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    func localEntranceQuad(scale: CGFloat) -> HomePerspectiveQuad {
        let rect = entranceBounds
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - rect.minX) * scale, y: (p.y - rect.minY) * scale)
        }
        let q = entranceQuad
        return HomePerspectiveQuad(topLeft: point(q.topLeft), topRight: point(q.topRight),
            bottomRight: point(q.bottomRight), bottomLeft: point(q.bottomLeft))
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
