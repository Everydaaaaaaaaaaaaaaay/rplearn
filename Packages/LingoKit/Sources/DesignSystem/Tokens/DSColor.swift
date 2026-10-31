import SwiftUI
import UIKit

public extension Color {
    /// 使用 UIKit dynamic provider 构造深浅模式自动切换的语义色。
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let dsSky = DSReadingPalette.tint
    static let dsSkyDeep = DSReadingPalette.tint
    static let dsCyan = Color(
        light: UIColor(red: 0, green: 0.749, blue: 0.780, alpha: 1),
        dark: UIColor(red: 0.2, green: 0.839, blue: 0.867, alpha: 1)
    )
    static let dsSunset = Color(
        light: UIColor(red: 1, green: 0.588, blue: 0, alpha: 1),
        dark: UIColor(red: 1, green: 0.702, blue: 0.251, alpha: 1)
    )
    /// 咕游记品牌围巾色：用于吉祥物相关引导与少量强调。
    static let dsBrandCoral = Color(
        light: UIColor(red: 1, green: 0.365, blue: 0.278, alpha: 1),
        dark: UIColor(red: 1, green: 0.482, blue: 0.408, alpha: 1)
    )
    /// 咕咕腹部与纸张的暖色基底。
    static let dsBrandCream = Color(
        light: UIColor(red: 1, green: 0.973, blue: 0.894, alpha: 1),
        dark: UIColor(red: 0.176, green: 0.157, blue: 0.125, alpha: 1)
    )
    /// 吉祥物描边对应的品牌深色。
    static let dsBrandInk = Color(
        light: UIColor(red: 0.027, green: 0.145, blue: 0.278, alpha: 1),
        dark: UIColor(red: 0.733, green: 0.894, blue: 1, alpha: 1)
    )
    /// 旅行工作台的实体深蓝：用于皮革、主操作和强调边缘，不随文字语义反转。
    static let dsTravelNavy = Color(
        light: UIColor(red: 0.035, green: 0.118, blue: 0.204, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.180, blue: 0.286, alpha: 1)
    )
    /// 纸面语义色；随系统外观切换，保持所有功能页一致。
    static let dsPaperInk = DSReadingPalette.ink
    static let dsPaperInkSecondary = DSReadingPalette.secondary
    /// 黑曜石徽章上的克制浮金，不作为大面积强调色。
    static let dsFoilGold = DSReadingPalette.gold
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
    static let dsBubbleIncoming = DSReadingPalette.paper
    static let dsBackground = DSReadingPalette.canvas
    static let dsSurface = DSReadingPalette.paper
    static let dsSurfaceMuted = DSReadingPalette.canvas
    static let dsBorder = DSReadingPalette.line
    /// 摄影场景上纸卡的语义文字色。
    static let dsSceneTextPrimary = DSReadingPalette.ink
    static let dsSceneTextSecondary = DSReadingPalette.secondary
    static let dsSceneTextTertiary = DSReadingPalette.secondary
}

public enum DSUIColor {
    public static let sky = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.686, green: 0.776, blue: 0.706, alpha: 1)
            : UIColor(red: 0.259, green: 0.408, blue: 0.365, alpha: 1)
    }
}
