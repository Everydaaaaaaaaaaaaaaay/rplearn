import SwiftUI
import UIKit

public enum DSTypography {
    /// SwiftUI 无法通过 fontDesign 覆盖 UIKit 导航标题，需单独配置 appearance。
    @MainActor
    public static func configureNavigationBarAppearance() {
        let large = UIFont.systemFont(ofSize: 34, weight: .bold)
        let inline = UIFont.systemFont(ofSize: 18, weight: .semibold)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: UIColor(DSReadingPalette.ink)]
        appearance.titleTextAttributes = [.font: inline, .foregroundColor: UIColor(DSReadingPalette.ink)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = DSUIColor.sky
    }
}
