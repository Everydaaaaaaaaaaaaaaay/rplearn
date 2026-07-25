import SwiftUI
import UIKit

public enum DSTypography {
    /// SwiftUI 无法通过 fontDesign 覆盖 UIKit 导航标题，需单独配置 appearance。
    @MainActor
    public static func configureNavigationBarAppearance() {
        let large = UIFont.systemFont(ofSize: 34, weight: .bold).rounded
        let inline = UIFont.systemFont(ofSize: 17, weight: .semibold).rounded
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [.font: large]
        appearance.titleTextAttributes = [.font: inline]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = DSUIColor.sky
    }
}

private extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
