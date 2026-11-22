import SwiftUI
import UIKit

public extension Color {
    /// 使用 UIKit dynamic provider 构造深浅模式自动切换的语义色。
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    // 旧令牌统一映射到蓬蓬（Puff）配色：未迁移完的零星调用与新页面使用同一套颜色，深浅模式一致。
    static let dsSky = PuffCandy.sky.base
    static let dsSkyDeep = PuffCandy.sky.deep
    static let dsCyan = PuffCandy.mint.base
    static let dsSunset = PuffCandy.tangerine.base
    /// 咕游记品牌围巾色：用于吉祥物相关引导与少量强调。
    static let dsBrandCoral = PuffCandy.tangerine.base
    /// 暖色浅底。
    static let dsBrandCream = PuffCandy.sunny.wash
    static let dsBrandInk = Puff.Palette.ink
    /// 实心主操作色，白字可读。
    static let dsTravelNavy = PuffCandy.sky.lip
    static let dsPaperInk = Puff.Palette.ink
    static let dsPaperInkSecondary = Puff.Palette.inkSoft
    static let dsFoilGold = PuffCandy.sunny.deep
    static let dsSuccess = PuffCandy.mint.base
    static let dsWarning = PuffCandy.sunny.base
    static let dsDanger = Puff.Palette.cherry
    static let dsCoach = PuffCandy.sunny.deep
    static let dsSpeech = PuffCandy.mint.deep
    static let dsQuiz = PuffCandy.grape.base
    static let dsBubbleIncoming = Puff.Palette.cloud
    static let dsBackground = Puff.Palette.page
    static let dsSurface = Puff.Palette.card
    static let dsSurfaceMuted = Puff.Palette.cloud
    static let dsBorder = Puff.Palette.line
    /// 摄影场景玻璃上的固定文字色。保持不透明，避免原生 vibrancy 按字符改变明暗。
    static let dsSceneTextPrimary = Color(
        light: UIColor(red: 0.035, green: 0.102, blue: 0.165, alpha: 1),
        dark: UIColor(red: 0.925, green: 0.961, blue: 0.988, alpha: 1)
    )
    static let dsSceneTextSecondary = Color(
        light: UIColor(red: 0.122, green: 0.188, blue: 0.259, alpha: 1),
        dark: UIColor(red: 0.757, green: 0.824, blue: 0.882, alpha: 1)
    )
    static let dsSceneTextTertiary = Color(
        light: UIColor(red: 0.216, green: 0.286, blue: 0.357, alpha: 1),
        dark: UIColor(red: 0.631, green: 0.714, blue: 0.788, alpha: 1)
    )
}

public enum DSUIColor {
    public static let sky = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.298, green: 0.761, blue: 1, alpha: 1)
            : UIColor(red: 0.106, green: 0.659, blue: 0.941, alpha: 1)
    }
}
