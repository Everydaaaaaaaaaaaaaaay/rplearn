import SwiftUI

/// 原图上的刚性图层。反向遮罩用于保留整间房屋，只露出门玻璃后的远景。
public struct DSSceneParallaxLayer: Sendable {
    public let contour: [CGPoint]
    public let depth: CGFloat
    public let inverted: Bool

    public init(contour: [CGPoint], depth: CGFloat, inverted: Bool = false) {
        self.contour = contour
        self.depth = depth
        self.inverted = inverted
    }

    public var bounds: CGRect {
        guard !inverted, let first = contour.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return contour.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    public func contains(_ p: CGPoint) -> Bool {
        guard contour.count >= 3 else { return false }
        var inside = false
        var previous = contour.last!
        for next in contour {
            if (next.y > p.y) != (previous.y > p.y),
               p.x < (previous.x - next.x) * (p.y - next.y) / (previous.y - next.y) + next.x {
                inside.toggle()
            }
            previous = next
        }
        return inverted ? !inside : inside
    }

    /// 所有像素和入口共用常量位移，轮廓内任意两点的距离保持不变。
    public func offset(camera: CGSize) -> CGSize {
        CGSize(width: camera.width * depth, height: camera.height * depth)
    }
}
