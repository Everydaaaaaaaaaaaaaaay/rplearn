import SwiftUI
import UIKit

public extension Color {
    /// 使用 UIKit dynamic provider 构造深浅模式自动切换的语义色。
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let dsSky = Color(
        light: UIColor(red: 0.106, green: 0.659, blue: 0.941, alpha: 1),
        dark: UIColor(red: 0.298, green: 0.761, blue: 1, alpha: 1)
    )
    static let dsSkyDeep = Color(
        light: UIColor(red: 0.078, green: 0.525, blue: 0.776, alpha: 1),
        dark: UIColor(red: 0.169, green: 0.529, blue: 0.741, alpha: 1)
    )
    static let dsCyan = Color(
        light: UIColor(red: 0, green: 0.749, blue: 0.780, alpha: 1),
        dark: UIColor(red: 0.2, green: 0.839, blue: 0.867, alpha: 1)
    )
    static let dsSunset = Color(
        light: UIColor(red: 1, green: 0.588, blue: 0, alpha: 1),
        dark: UIColor(red: 1, green: 0.702, blue: 0.251, alpha: 1)
    )
    static let dsSuccess = Color(
        light: UIColor(red: 0.184, green: 0.749, blue: 0.388, alpha: 1),
        dark: UIColor(red: 0.290, green: 0.871, blue: 0.502, alpha: 1)
    )
    static let dsWarning = Color(
        light: UIColor(red: 0.961, green: 0.655, blue: 0, alpha: 1),
        dark: UIColor(red: 1, green: 0.788, blue: 0.239, alpha: 1)
    )
    static let dsDanger = Color(
        light: UIColor(red: 1, green: 0.294, blue: 0.294, alpha: 1),
        dark: UIColor(red: 1, green: 0.420, blue: 0.420, alpha: 1)
    )
    static let dsCoach = Color(
        light: UIColor(red: 0.820, green: 0.557, blue: 0, alpha: 1),
        dark: UIColor(red: 1, green: 0.788, blue: 0.239, alpha: 1)
    )
    static let dsSpeech = Color(
        light: UIColor(red: 0.055, green: 0.608, blue: 0.686, alpha: 1),
        dark: UIColor(red: 0.208, green: 0.792, blue: 0.875, alpha: 1)
    )
    static let dsQuiz = Color(
        light: UIColor(red: 0.478, green: 0.353, blue: 0.973, alpha: 1),
        dark: UIColor(red: 0.655, green: 0.545, blue: 0.980, alpha: 1)
    )
    static let dsBubbleIncoming = Color(
        light: UIColor(red: 0.937, green: 0.957, blue: 0.976, alpha: 1),
        dark: UIColor(red: 0.149, green: 0.169, blue: 0.200, alpha: 1)
    )
    static let dsBackground = Color(
        light: UIColor(red: 0.953, green: 0.973, blue: 0.988, alpha: 1),
        dark: UIColor(red: 0.078, green: 0.094, blue: 0.114, alpha: 1)
    )
    static let dsSurface = Color(
        light: .white,
        dark: UIColor(red: 0.118, green: 0.141, blue: 0.169, alpha: 1)
    )
    static let dsBorder = Color(
        light: UIColor(red: 0.894, green: 0.929, blue: 0.957, alpha: 1),
        dark: UIColor.white.withAlphaComponent(0.08)
    )
}

public enum DSUIColor {
    public static let sky = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.298, green: 0.761, blue: 1, alpha: 1)
            : UIColor(red: 0.106, green: 0.659, blue: 0.941, alpha: 1)
    }
}
