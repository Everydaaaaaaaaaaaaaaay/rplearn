import SwiftUI
import UIKit

/// Shared with the approved native visual baseline. Scene composition stays in each Feature.
public enum DSReadingPalette {
    public static let canvas = adaptive(0xF1F1EA, 0x141D19)
    public static let paper = adaptive(0xFAF6EA, 0x222D27)
    public static let ink = adaptive(0x25352E, 0xF0EFE4)
    public static let secondary = adaptive(0x687369, 0xB4BCAF)
    public static let primary = adaptive(0x2C4338, 0xB6C6AA)
    public static let onPrimary = adaptive(0xFFFDF3, 0x18271E)
    public static let tint = adaptive(0x42685D, 0xAFC6B4)
    public static let gold = Color(red: 0.74, green: 0.61, blue: 0.38)
    public static var line: Color { ink.opacity(0.12) }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}
