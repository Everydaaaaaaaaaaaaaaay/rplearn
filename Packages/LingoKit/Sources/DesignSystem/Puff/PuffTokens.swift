import SwiftUI
import UIKit

/// 蓬蓬（Puff）设计系统：白色为底、糖果色点缀、圆润字形、可按压的“厚卡片”和弹性动效。
/// 面向儿童与青少年，同时保持成人可接受的克制：颜色只做点缀，正文始终是深墨色。
///
/// 旧的 `DS*` 令牌仍服务尚未迁移的页面；新页面只使用 `Puff`。
public enum Puff {}

// MARK: - 颜色

private extension UIColor {
    convenience init(puffHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private func puffColor(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(light: UIColor(puffHex: light), dark: UIColor(puffHex: dark))
}

public extension Puff {
    /// 中性色。浅色以纯白为主基调；深色是柔和的夜空蓝，而不是纯黑。
    enum Palette {
        /// 页面底色。
        public static let page = puffColor(0xFFFFFF, 0x161A2E)
        /// 卡片正面。
        public static let card = puffColor(0xFFFFFF, 0x21263F)
        /// 搜索框、按压态、次级填充。
        public static let cloud = puffColor(0xF3F6FC, 0x2A3050)
        /// 卡片描边。
        public static let line = puffColor(0xE8ECF5, 0x323859)
        /// 厚卡片底部的“唇边”，制造可按下去的实体感。
        public static let lip = puffColor(0xDFE5F0, 0x0F1226)
        /// 正文墨色。
        public static let ink = puffColor(0x2A3052, 0xF3F5FF)
        public static let inkSoft = puffColor(0x666D8F, 0xB6BBD8)
        public static let inkFaint = puffColor(0x9CA2BD, 0x7F86AA)
        /// 未读角标。
        public static let cherry = puffColor(0xFF5470, 0xFF6F86)
    }
}

/// 一组糖果色：`base` 填充、`deep` 白底上的图标与强调字、`wash` 浅底、`lip` 实心按钮的唇边。
public struct PuffCandy: Sendable, Equatable {
    public let base: Color
    public let deep: Color
    public let wash: Color
    public let lip: Color

    init(base: (UInt32, UInt32), deep: (UInt32, UInt32), wash: (UInt32, UInt32), lip: (UInt32, UInt32)) {
        self.base = puffColor(base.0, base.1)
        self.deep = puffColor(deep.0, deep.1)
        self.wash = puffColor(wash.0, wash.1)
        self.lip = puffColor(lip.0, lip.1)
    }

    public static let sky = PuffCandy(
        base: (0x4DA6FF, 0x5AAEFF), deep: (0x2577D9, 0x8CC6FF),
        wash: (0xEAF4FF, 0x1E3157), lip: (0x2F86E6, 0x1D5CA8)
    )
    public static let bubblegum = PuffCandy(
        base: (0xFF7EAA, 0xFF8AB3), deep: (0xD9437A, 0xFFA8C7),
        wash: (0xFFEDF3, 0x3A2440), lip: (0xE65C8E, 0xA83A66)
    )
    public static let sunny = PuffCandy(
        base: (0xFFC53D, 0xFFCB52), deep: (0xB97A00, 0xFFD877),
        wash: (0xFFF6DC, 0x3A3224), lip: (0xE6A21F, 0xA67614)
    )
    public static let mint = PuffCandy(
        base: (0x3DD39A, 0x45D9A1), deep: (0x14935F, 0x7BE6BD),
        wash: (0xE3F9F0, 0x183B36), lip: (0x22B47C, 0x168058)
    )
    public static let grape = PuffCandy(
        base: (0x9B7BFF, 0xA68AFF), deep: (0x6A47E0, 0xC4B2FF),
        wash: (0xF1ECFF, 0x2B2652), lip: (0x7E5CF0, 0x5A3FBF)
    )
    public static let tangerine = PuffCandy(
        base: (0xFF9A4D, 0xFFA55E), deep: (0xC9621A, 0xFFBE8A),
        wash: (0xFFF0E4, 0x3A2A26), lip: (0xE87D2E, 0xA9581C)
    )

    public static let all: [PuffCandy] = [.sky, .bubblegum, .sunny, .mint, .grape, .tangerine]

    /// 名字决定的稳定颜色：同一位朋友在任何页面都是同一种颜色。
    public static func stable(for name: String) -> PuffCandy {
        let value = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return all[Int(value.magnitude % UInt(all.count))]
    }
}

// MARK: - 尺寸

public extension Puff {
    enum Radius {
        public static let small: CGFloat = 12
        public static let medium: CGFloat = 18
        public static let large: CGFloat = 24
        public static let huge: CGFloat = 30
    }

    enum Space {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let s: CGFloat = 12
        public static let m: CGFloat = 16
        public static let l: CGFloat = 20
        public static let xl: CGFloat = 28
    }

    /// 厚卡片唇边高度。
    enum Lip {
        public static let card: CGFloat = 4
        public static let button: CGFloat = 4
        public static let chip: CGFloat = 3
    }
}

// MARK: - 动效

public extension Puff {
    /// 动效都使用弹簧，可被新的手势打断；“减弱动态效果”时统一降级为短淡入淡出。
    enum Motion {
        /// 手指按下：快速陷下去。
        public static let press = Animation.spring(response: 0.18, dampingFraction: 0.7)
        /// 松手：带一点回弹。
        public static let release = Animation.spring(response: 0.34, dampingFraction: 0.5)
        /// 角标、星星等小元素弹出。
        public static let pop = Animation.spring(response: 0.4, dampingFraction: 0.55)
        /// 分组展开、筛选切换等布局变化。
        public static let bouncy = Animation.spring(response: 0.46, dampingFraction: 0.72)
        /// 大块内容的平稳过渡。
        public static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.9)
        /// 实心按钮松手后像果冻一样晃两下。
        public static let jelly = Animation.spring(response: 0.42, dampingFraction: 0.42)
        /// 新消息、新卡片从锚点弹出来。
        public static let arrival = Animation.spring(response: 0.38, dampingFraction: 0.62)

        /// 列表首次出现时逐行错峰进入。
        public static func entrance(_ index: Int) -> Animation {
            .spring(response: 0.55, dampingFraction: 0.78).delay(Double(min(max(index, 0), 10)) * 0.045)
        }

        public static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.18) : animation
        }
    }
}

// MARK: - 字体

public extension Puff {
    /// 字重层级。圆体字形本身显粗，整体比常规界面低一档：
    /// 页面大标题 bold，卡片标题与名字 semibold，按钮与强调 semibold，标签与辅助文字 medium，正文 regular。
    enum Weight {
        public static let display: Font.Weight = .bold
        public static let title: Font.Weight = .semibold
        public static let emphasis: Font.Weight = .semibold
        public static let label: Font.Weight = .medium
        public static let body: Font.Weight = .regular
        /// 图标线条与文字协调，比文字略粗一点即可。
        public static let icon: Font.Weight = .semibold
    }
}

public extension Font {
    /// 圆体字形，跟随动态字体。
    static func puff(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}
