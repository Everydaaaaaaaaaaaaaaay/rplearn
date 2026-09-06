import UIKit

/// Resolves legacy character asset names without changing their persisted identity keys.
@MainActor
enum DSAvatarAssets {
    static func image(named name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        if let image = UIImage(named: name) { return image }
        switch name {
        case "avatar_oliver": return oliverPortrait
        default: return nil
        }
    }

    // Display the face and shoulders of the canonical story sprite. Cache the crop so
    // list refreshes do not decode and crop the full sprite for every avatar view.
    private static let oliverPortrait: UIImage? = {
        guard let source = UIImage(named: "oliver_neutral"),
              let pixels = source.cgImage else { return nil }
        let width = CGFloat(pixels.width)
        let side = (width * 0.5).rounded()
        let rect = CGRect(x: (width * 0.24).rounded(), y: 0, width: side, height: side)
        guard let portrait = pixels.cropping(to: rect) else { return nil }
        return UIImage(cgImage: portrait, scale: source.scale, orientation: source.imageOrientation)
    }()
}
