import SwiftUI
import UIKit

/// Persisted avatar keys resolve to the shared P3R portraits without changing story artwork.
@MainActor
enum DSAvatarAssets {
    static func image(named name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        let portraitName: String = switch name {
        case "avatar_oliver": "avatar_p3r_oliver"
        case "avatar_ruby": "avatar_p3r_ruby"
        case "avatar_marcus": "avatar_p3r_marcus"
        default: name
        }
        if let image = UIImage(named: portraitName) { return image }
        if portraitName.hasSuffix(".webp"),
           let url = Bundle.main.url(forResource: String(portraitName.dropLast(5)), withExtension: "webp") {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(named: name)
    }

    static func presentation(named name: String?) -> (alignment: Alignment, scale: CGFloat, yOffset: CGFloat) {
        (.center, 1, 0)
    }
}
