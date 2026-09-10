import SwiftUI
import UIKit

/// Avatar assets retain their persisted names independently of story pose variants.
@MainActor
enum DSAvatarAssets {
    static func image(named name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        if let image = UIImage(named: name) {
            return image
        }
        // The starter characters share the reviewed Departures portrait set. Keep the
        // persisted stable avatar keys while resolving their bundled neutral artwork.
        let bundledPortraitName: String? = switch name {
        case "avatar_ruby": "dp_ruby_open"
        case "avatar_marcus": "dp_marcus_print"
        default: nil
        }
        return bundledPortraitName.flatMap(UIImage.init(named:))
    }

    static func presentation(named name: String?) -> (alignment: Alignment, scale: CGFloat, yOffset: CGFloat) {
        switch name {
        case "avatar_ruby":
            // Ruby 的源图是全身站姿；放大到头肩构图，避免圆形头像上半部出现大块留白。
            return (.top, 1.95, -2)
        case "avatar_marcus":
            // Marcus 的人物在源画布中更窄，需比 Ruby 再放大一些才能与 Oliver 视觉等重。
            return (.top, 2.25, -3)
        default:
            return (.center, 1, 0)
        }
    }
}
