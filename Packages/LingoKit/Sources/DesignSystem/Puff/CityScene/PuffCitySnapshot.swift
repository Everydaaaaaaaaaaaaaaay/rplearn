import SwiftUI
import UIKit

/// 把卡通城市渲染成静态图片，供 UIKit 视图（例如地图图钉）使用。结果按参数缓存。
@MainActor
public enum PuffCitySnapshot {
    private static var cache: [String: UIImage] = [:]

    /// - Parameter focusWidth: 画面横向容纳的设计单位数。越小越“拉近”，小图标建议 140 左右，
    ///   只保留地标与地面、裁掉大部分天空。
    /// 圆形小图标：以城市地标为中心拉近，车辆不入画。
    public static func icon(regionID: String, size: CGSize) -> UIImage? {
        let recipe = PuffCityCatalog.recipe(for: regionID)
        return image(regionID: regionID, size: size, viewport: .focus(recipe.iconX), focusWidth: 150)
    }

    public static func image(
        regionID: String,
        size: CGSize,
        viewport: PuffCityScene.Viewport = .west,
        mood: PuffSceneMood = .day,
        focusWidth: CGFloat? = nil
    ) -> UIImage? {
        let key = "\(regionID)-\(Int(size.width))x\(Int(size.height))-\(viewport)-\(mood)-\(Int(focusWidth ?? 0))"
        if let cached = cache[key] { return cached }
        let recipe = PuffCityCatalog.recipe(for: regionID)
        let viewportWidth = viewport.range.upperBound - viewport.range.lowerBound
        let unit = focusWidth.map { size.width / $0 }
        let canvasSize = unit.map {
            CGSize(width: viewportWidth * $0, height: max(size.height, PuffScenePainter.height * $0))
        } ?? size
        let canvas = PuffCitySceneCanvas(
            recipe: recipe,
            mood: mood,
            clock: DateComponents(hour: 10, minute: 10),
            viewport: viewport,
            isPaused: true,
            fixedTime: 0
        )
        .frame(width: canvasSize.width, height: canvasSize.height)
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .clipped()
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = UITraitCollection.current.displayScale > 0 ? UITraitCollection.current.displayScale : 3
        guard let image = renderer.uiImage else { return nil }
        cache[key] = image
        return image
    }
}
