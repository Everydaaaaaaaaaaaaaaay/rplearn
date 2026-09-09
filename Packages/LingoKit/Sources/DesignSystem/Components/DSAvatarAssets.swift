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
        case "avatar_ruby", "avatar_marcus":
            // These reviewed source portraits are tall character poses. A top-biased,
            // modestly enlarged crop turns them into legible head-and-shoulder badges.
            return (.top, 1.48, 6)
        default:
            return (.center, 1, 0)
        }
    }
}
