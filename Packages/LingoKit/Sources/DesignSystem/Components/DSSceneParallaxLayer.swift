import SwiftUI

/// 原图上的刚性图层。反向遮罩用于保留整间房屋，只露出门玻璃后的远景。
public struct DSSceneParallaxLayer: Sendable {
    public let contour: [CGPoint]
    public let additionalContours: [[CGPoint]]
    public var contours: [[CGPoint]] { [contour] + additionalContours }
    public let depth: CGFloat
    public let inverted: Bool

    public init(contour: [CGPoint], depth: CGFloat, inverted: Bool = false, additionalContours: [[CGPoint]] = []) {
        self.contour = contour
        self.additionalContours = additionalContours
        self.depth = depth
        self.inverted = inverted
    }

    public var bounds: CGRect {
        let points = contours.flatMap { $0 }
        guard !inverted, let first = points.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    public func contains(_ p: CGPoint) -> Bool {
        let inside = contours.contains { polygon in
            guard polygon.count >= 3 else { return false }
            var inside = false
            var previous = polygon.last!
            for next in polygon {
                if (next.y > p.y) != (previous.y > p.y),
                   p.x < (previous.x - next.x) * (p.y - next.y) / (previous.y - next.y) + next.x {
                    inside.toggle()
                }
                previous = next
            }
            return inside
        }
        return inverted ? !inside : inside
    }

    /// 所有像素和入口共用常量位移，轮廓内任意两点的距离保持不变。
    public func offset(camera: CGSize) -> CGSize {
        CGSize(width: camera.width * depth, height: camera.height * depth)
    }
}
