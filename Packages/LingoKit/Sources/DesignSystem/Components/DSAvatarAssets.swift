import UIKit

/// Avatar assets retain their persisted names independently of story pose variants.
@MainActor
enum DSAvatarAssets {
    static func image(named name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        return UIImage(named: name)
    }
}
