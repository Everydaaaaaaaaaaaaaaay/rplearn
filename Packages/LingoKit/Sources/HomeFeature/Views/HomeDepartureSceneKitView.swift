import CoreImage
import QuartzCore
import SceneKit
import SwiftUI
import UIKit

/// 首页的空间视觉层。文字和图标都是 SceneKit 几何体，不使用预模糊贴图叠层。
/// 导航、命中区和无障碍继续由上层 SwiftUI 承担。
@MainActor
struct HomeDepartureSceneKitView: UIViewRepresentable {
    let layout: HomeDepartureSceneLayout
    let flag: String?
    let cityName: String?
    let storySubtitle: String
    let pressedEntry: HomeSceneEntryID?
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(
            frame: .zero,
            options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue]
        )
        view.backgroundColor = UIColor.clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        context.coordinator.installScene(in: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(
            view: view,
            layout: layout,
            flag: flag,
            cityName: cityName,
            storySubtitle: storySubtitle,
            pressedEntry: pressedEntry,
            reduceMotion: reduceMotion
        )
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.scene = nil
    }

    @MainActor
    final class Coordinator {
        private var contentKey = ""
        private var lastPressedEntry: HomeSceneEntryID?
        private var entryNodes: [HomeSceneEntryID: SCNNode] = [:]
        private var basePositions: [HomeSceneEntryID: SCNVector3] = [:]
        private var baseScales: [HomeSceneEntryID: SCNVector3] = [:]

        func installScene(in view: SCNView) {
            let scene = SCNScene()
            scene.background.contents = UIColor.clear
            view.scene = scene
            installCamera(in: scene, view: view)
            installLighting(in: scene)
        }

        func update(
            view: SCNView,
            layout: HomeDepartureSceneLayout,
            flag: String?,
            cityName: String?,
            storySubtitle: String,
            pressedEntry: HomeSceneEntryID?,
            reduceMotion: Bool
        ) {
            let nextKey = [layout.assetName, flag ?? "", cityName ?? "", storySubtitle].joined(separator: "|")
            if nextKey != contentKey {
                contentKey = nextKey
                rebuildContent(
                    in: view,
                    layout: layout,
                    flag: flag,
                    cityName: cityName,
                    storySubtitle: storySubtitle
                )
                lastPressedEntry = nil
            }

            guard pressedEntry != lastPressedEntry else { return }
            applyPressState(pressedEntry, reduceMotion: reduceMotion)
            lastPressedEntry = pressedEntry
        }

        private func installCamera(in scene: SCNScene, view: SCNView) {
            let cameraNode = SCNNode()
            let camera = SCNCamera()
            let verticalFieldOfView = 31.5
            let distance = (HomeDepartureCanvas.height / 2) / tan(verticalFieldOfView * .pi / 360)
            camera.fieldOfView = verticalFieldOfView
            camera.projectionDirection = .vertical
            camera.zNear = 10
            camera.zFar = Double(distance + 500)
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = false
            camera.exposureOffset = 0.22
            // 只有真实几何体的高亮边缘会触发 Bloom；不再叠加预模糊副本。
            camera.bloomIntensity = 0.065
            camera.bloomThreshold = 1.00
            camera.bloomBlurRadius = 3.4
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, Float(distance))
            cameraNode.name = "home-camera"
            scene.rootNode.addChildNode(cameraNode)
            view.pointOfView = cameraNode
        }

        private func installLighting(in scene: SCNScene) {
            let ambientNode = SCNNode()
            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = UIColor(red: 1, green: 0.90, blue: 0.76, alpha: 1)
            ambient.intensity = 125
            ambientNode.light = ambient
            ambientNode.name = "home-ambient"
            scene.rootNode.addChildNode(ambientNode)

            let keyNode = SCNNode()
            let key = SCNLight()
            key.type = .directional
            key.color = UIColor(red: 1, green: 0.975, blue: 0.92, alpha: 1)
            key.intensity = 850
            keyNode.light = key
            keyNode.eulerAngles = SCNVector3(-0.24, 0.34, -0.08)
            keyNode.name = "home-key-light"
            scene.rootNode.addChildNode(keyNode)
        }

        private func rebuildContent(
            in view: SCNView,
            layout: HomeDepartureSceneLayout,
            flag: String?,
            cityName: String?,
            storySubtitle: String
        ) {
            guard let scene = view.scene else { return }
            scene.rootNode.childNodes
                .filter { !["home-camera", "home-ambient", "home-key-light"].contains($0.name ?? "") }
                .forEach { $0.removeFromParentNode() }
            entryNodes.removeAll(keepingCapacity: true)
            basePositions.removeAll(keepingCapacity: true)
            baseScales.removeAll(keepingCapacity: true)

            let background = UIImage(named: layout.assetName, in: .main, compatibleWith: nil)
            let sampler = HomeSceneBackgroundSampler(image: background)

            if let flag, let cityName {
                let sample = sampler.sample(around: layout.location, canvasSize: canvasSize)
                let node = HomeSceneGeometry.location(flag: flag, cityName: cityName, sample: sample)
                applyPlane(layout.location, to: node)
                node.name = "location"
                scene.rootNode.addChildNode(node)
            }

            addEntry(
                id: .map,
                icon: .map,
                title: "世界地图",
                subtitle: nil,
                iconSize: 34,
                titleSize: 20,
                layout: layout.map,
                sampler: sampler,
                scene: scene
            )
            addEntry(
                id: .story,
                icon: .story,
                title: "剧情",
                subtitle: storySubtitle,
                iconSize: 36,
                titleSize: 21,
                layout: layout.story,
                sampler: sampler,
                scene: scene
            )
            addEntry(
                id: .activities,
                icon: .activities,
                title: "城市活动",
                subtitle: nil,
                iconSize: 36,
                titleSize: 20,
                layout: layout.activities,
                sampler: sampler,
                scene: scene
            )
        }

        private func addEntry(
            id: HomeSceneEntryID,
            icon: HomeSceneGeometry.Icon,
            title: String,
            subtitle: String?,
            iconSize: CGFloat,
            titleSize: CGFloat,
            layout: HomeDepartureHotspotLayout,
            sampler: HomeSceneBackgroundSampler,
            scene: SCNScene
        ) {
            let sample = sampler.sample(around: layout, canvasSize: canvasSize)
            let node = HomeSceneGeometry.entry(
                icon: icon,
                title: title,
                subtitle: subtitle,
                iconSize: iconSize,
                titleSize: titleSize,
                sample: sample
            )
            applyPlane(layout, to: node)
            node.name = id.rawValue
            scene.rootNode.addChildNode(node)
            entryNodes[id] = node
            basePositions[id] = node.position
            baseScales[id] = node.scale
        }

        private func applyPlane(_ layout: HomeDepartureHotspotLayout, to node: SCNNode) {
            let plane = layout.plane
            node.position = scenePosition(center: layout.center, z: plane.lift)
            node.eulerAngles = SCNVector3(
                degreesToRadians(plane.rotationX),
                degreesToRadians(plane.rotationY),
                degreesToRadians(plane.rotationZ)
            )
            node.scale = SCNVector3(Float(plane.scaleX), Float(plane.scaleY), 1)
        }

        private func applyPressState(_ pressedEntry: HomeSceneEntryID?, reduceMotion: Bool) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = reduceMotion ? 0.12 : (pressedEntry == nil ? 0.24 : 0.085)
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(
                name: pressedEntry == nil ? .easeInEaseOut : .easeOut
            )
            for (id, node) in entryNodes {
                guard let basePosition = basePositions[id], let baseScale = baseScales[id] else { continue }
                let isPressed = pressedEntry == id
                node.position = SCNVector3(
                    basePosition.x,
                    basePosition.y,
                    basePosition.z - (isPressed ? 3.8 : 0)
                )
                let scale: Float = isPressed && !reduceMotion ? 0.97 : 1
                node.scale = SCNVector3(baseScale.x * scale, baseScale.y * scale, baseScale.z)
            }
            SCNTransaction.commit()
        }

        private var canvasSize: CGSize {
            CGSize(width: HomeDepartureCanvas.width, height: HomeDepartureCanvas.height)
        }

        private func scenePosition(center: UnitPoint, z: CGFloat) -> SCNVector3 {
            SCNVector3(
                Float(HomeDepartureCanvas.width * center.x - HomeDepartureCanvas.width / 2),
                Float(HomeDepartureCanvas.height / 2 - HomeDepartureCanvas.height * center.y),
                Float(z)
            )
        }

        private func degreesToRadians(_ degrees: Double) -> Float {
            Float(degrees * .pi / 180)
        }
    }
}

private struct HomeSceneBackgroundSample {
    let luminance: CGFloat
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    static let neutral = HomeSceneBackgroundSample(luminance: 0.48, red: 0.5, green: 0.48, blue: 0.44)
}

@MainActor
private struct HomeSceneBackgroundSampler {
    private let image: UIImage?
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    init(image: UIImage?) {
        self.image = image
    }

    func sample(around layout: HomeDepartureHotspotLayout, canvasSize: CGSize) -> HomeSceneBackgroundSample {
        guard let image, let input = CIImage(image: image) else { return .neutral }
        let extent = input.extent
        let normalizedWidth = min(0.28, max(0.08, layout.hitSize.width / canvasSize.width * 0.72))
        let normalizedHeight = min(0.20, max(0.055, layout.hitSize.height / canvasSize.height * 0.72))
        let rect = CGRect(
            x: extent.width * (layout.center.x - normalizedWidth / 2),
            y: extent.height * (1 - layout.center.y - normalizedHeight / 2),
            width: extent.width * normalizedWidth,
            height: extent.height * normalizedHeight
        ).intersection(extent)
        guard !rect.isEmpty,
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input,
                  kCIInputExtentKey: CIVector(cgRect: rect),
              ]),
              let output = filter.outputImage
        else {
            return .neutral
        }

        var pixels = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixels,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        let red = CGFloat(pixels[0]) / 255
        let green = CGFloat(pixels[1]) / 255
        let blue = CGFloat(pixels[2]) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return HomeSceneBackgroundSample(luminance: luminance, red: red, green: green, blue: blue)
    }
}

@MainActor
private enum HomeSceneGeometry {
    enum Icon {
        case map
        case story
        case activities
    }

    private struct VisualNode {
        let node: SCNNode
        let size: CGSize
    }

    static func entry(
        icon: Icon,
        title: String,
        subtitle: String?,
        iconSize: CGFloat,
        titleSize: CGFloat,
        sample: HomeSceneBackgroundSample
    ) -> SCNNode {
        let root = SCNNode()
        let materials = sceneMaterials(sample: sample)
        let iconNode = iconNode(icon, size: iconSize, materials: materials)
        let titleNode = textNode(title, size: titleSize, weight: .medium, materials: materials)
        let subtitleNode = subtitle.map {
            textNode($0, size: 11, weight: .regular, materials: materials)
        }

        let spacing: CGFloat = subtitle == nil ? 5 : 4
        let subtitleSpacing: CGFloat = 2
        let totalHeight = iconNode.size.height
            + spacing
            + titleNode.size.height
            + (subtitleNode.map { subtitleSpacing + $0.size.height } ?? 0)
        var cursor = totalHeight / 2

        iconNode.node.position.y = Float(cursor - iconNode.size.height / 2)
        cursor -= iconNode.size.height + spacing
        titleNode.node.position.y = Float(cursor - titleNode.size.height / 2)
        cursor -= titleNode.size.height
        if let subtitleNode {
            cursor -= subtitleSpacing
            subtitleNode.node.position.y = Float(cursor - subtitleNode.size.height / 2)
            root.addChildNode(subtitleNode.node)
        }

        root.addChildNode(iconNode.node)
        root.addChildNode(titleNode.node)
        return root
    }

    static func location(flag: String, cityName: String, sample: HomeSceneBackgroundSample) -> SCNNode {
        let root = SCNNode()
        let materials = sceneMaterials(sample: sample, emissionScale: 0.48)
        let city = textNode(cityName, size: 20, weight: .medium, materials: materials, horizontalAnchor: .leading)
        let caption = textNode("当前驻地", size: 11, weight: .regular, materials: materials, horizontalAnchor: .leading)
        let flagNode = flagPlane(flag)

        let contentHeight = max(flagNode.size.height, city.size.height + caption.size.height + 1)
        let left = -((flagNode.size.width + 7 + max(city.size.width, caption.size.width)) / 2)
        flagNode.node.position = SCNVector3(
            Float(left + flagNode.size.width / 2),
            0,
            0.2
        )
        let textX = left + flagNode.size.width + 7
        city.node.position = SCNVector3(
            Float(textX),
            Float(contentHeight / 2 - city.size.height / 2),
            0
        )
        caption.node.position = SCNVector3(
            Float(textX),
            Float(-contentHeight / 2 + caption.size.height / 2),
            0
        )
        root.addChildNode(flagNode.node)
        root.addChildNode(city.node)
        root.addChildNode(caption.node)
        return root
    }

    private enum HorizontalAnchor {
        case center
        case leading
    }

    private static func textNode(
        _ value: String,
        size: CGFloat,
        weight: UIFont.Weight,
        materials: [SCNMaterial],
        horizontalAnchor: HorizontalAnchor = .center
    ) -> VisualNode {
        let text = SCNText(string: value, extrusionDepth: max(0.78, size * 0.052))
        text.font = roundedFont(size: size, weight: weight)
        // 20pt 左右的手机字号无需印刷级曲线细分；该值兼顾 4× MSAA 边缘与首页首帧速度。
        text.flatness = 0.22
        text.chamferRadius = max(0.10, size * 0.007)
        text.materials = materials

        let node = SCNNode(geometry: text)
        let bounds = text.boundingBox
        let width = CGFloat(bounds.max.x - bounds.min.x)
        let height = CGFloat(bounds.max.y - bounds.min.y)
        let pivotX = horizontalAnchor == .center
            ? (bounds.min.x + bounds.max.x) / 2
            : bounds.min.x
        node.pivot = SCNMatrix4MakeTranslation(
            pivotX,
            (bounds.min.y + bounds.max.y) / 2,
            bounds.min.z
        )
        return VisualNode(node: node, size: CGSize(width: width, height: height))
    }

    private static func sceneMaterials(
        sample: HomeSceneBackgroundSample,
        emissionScale: CGFloat = 1
    ) -> [SCNMaterial] {
        let darkness = max(0, min(1, 1 - sample.luminance))
        let warmth = max(0, min(1, (sample.red - sample.blue + 0.22) / 0.44))
        let frontColor = UIColor(
            red: 0.985,
            green: 0.975 - warmth * 0.008,
            blue: 0.875 - warmth * 0.020,
            alpha: 1
        )
        let emissionColor = UIColor(red: 1, green: 0.80, blue: 0.42, alpha: 1)

        let front = SCNMaterial()
        front.lightingModel = .physicallyBased
        front.diffuse.contents = frontColor
        front.roughness.contents = 0.38
        front.metalness.contents = 0.035
        front.emission.contents = emissionColor
        front.emission.intensity = (0.045 + darkness * 0.060) * emissionScale

        let back = SCNMaterial()
        back.lightingModel = .physicallyBased
        back.diffuse.contents = UIColor(red: 0.45, green: 0.30, blue: 0.12, alpha: 1)
        back.roughness.contents = 0.64
        back.emission.contents = emissionColor
        back.emission.intensity = 0.008 * emissionScale

        let side = SCNMaterial()
        side.lightingModel = .physicallyBased
        side.diffuse.contents = UIColor(red: 0.54, green: 0.36, blue: 0.13, alpha: 1)
        side.roughness.contents = 0.53
        side.metalness.contents = 0.06
        side.emission.contents = emissionColor
        side.emission.intensity = (0.004 + darkness * 0.008) * emissionScale

        let chamfer = SCNMaterial()
        chamfer.lightingModel = .physicallyBased
        chamfer.diffuse.contents = UIColor(red: 1, green: 0.96, blue: 0.79, alpha: 1)
        chamfer.roughness.contents = 0.26
        chamfer.metalness.contents = 0.05
        chamfer.emission.contents = emissionColor
        chamfer.emission.intensity = (0.007 + darkness * 0.014) * emissionScale
        return [front, back, side, chamfer]
    }

    private static func iconNode(_ icon: Icon, size: CGFloat, materials: [SCNMaterial]) -> VisualNode {
        let root = SCNNode()
        let unit = size / 36
        switch icon {
        case .map:
            addPolyline(
                [
                    CGPoint(x: -15, y: 10), CGPoint(x: -5, y: 14), CGPoint(x: 5, y: 9),
                    CGPoint(x: 15, y: 13), CGPoint(x: 15, y: -11), CGPoint(x: 5, y: -8),
                    CGPoint(x: -5, y: -13), CGPoint(x: -15, y: -9),
                ],
                closed: true,
                thickness: 2.05,
                unit: unit,
                materials: materials,
                to: root
            )
            addPolyline(
                [CGPoint(x: -5, y: 13.5), CGPoint(x: -5, y: -12.5)],
                thickness: 1.65,
                unit: unit,
                materials: materials,
                to: root
            )
            addPolyline(
                [CGPoint(x: 5, y: 8.8), CGPoint(x: 5, y: -7.8)],
                thickness: 1.65,
                unit: unit,
                materials: materials,
                to: root
            )
            let route = [
                CGPoint(x: -11, y: -3), CGPoint(x: -7, y: 3), CGPoint(x: -3, y: 4.5),
                CGPoint(x: 0, y: 0), CGPoint(x: 4, y: -3.5), CGPoint(x: 7, y: 0), CGPoint(x: 10, y: 3),
            ]
            addPolyline(route, thickness: 0.95, unit: unit, materials: materials, to: root)
            for point in [route[0], route[3], route[6]] {
                addDisc(at: point, radius: 1.2, unit: unit, materials: materials, to: root)
            }

        case .story:
            addPolyline(
                [
                    CGPoint(x: 0, y: 12), CGPoint(x: -5, y: 14), CGPoint(x: -11, y: 13),
                    CGPoint(x: -16, y: 9), CGPoint(x: -16, y: -12), CGPoint(x: -10, y: -13),
                    CGPoint(x: -5, y: -12), CGPoint(x: 0, y: -9),
                ],
                thickness: 2.0,
                unit: unit,
                materials: materials,
                to: root
            )
            addPolyline(
                [
                    CGPoint(x: 0, y: 12), CGPoint(x: 5, y: 14), CGPoint(x: 11, y: 13),
                    CGPoint(x: 16, y: 9), CGPoint(x: 16, y: -12), CGPoint(x: 10, y: -13),
                    CGPoint(x: 5, y: -12), CGPoint(x: 0, y: -9), CGPoint(x: 0, y: 12),
                ],
                thickness: 2.0,
                unit: unit,
                materials: materials,
                to: root
            )
            addPolyline(
                [
                    CGPoint(x: -12, y: -1), CGPoint(x: -7, y: -1), CGPoint(x: -4, y: 5),
                    CGPoint(x: 1, y: -6), CGPoint(x: 5, y: 3), CGPoint(x: 9, y: -1), CGPoint(x: 13, y: -1),
                ],
                thickness: 1.55,
                unit: unit,
                materials: materials,
                to: root
            )

        case .activities:
            addDisc(at: CGPoint(x: -5.5, y: 12.5), radius: 3.5, unit: unit, materials: materials, to: root)
            addPolyline(
                [CGPoint(x: -5.5, y: 8), CGPoint(x: -3, y: 0.5), CGPoint(x: 2, y: -3)],
                thickness: 2.45,
                unit: unit,
                materials: materials,
                to: root
            )
            addPolyline(
                [CGPoint(x: -4, y: 4), CGPoint(x: -10, y: -1)],
                thickness: 2.25,
                unit: unit,
                materials: materials,
                to: root
            )
            addPolyline(
                [CGPoint(x: -3, y: 0.5), CGPoint(x: -8, y: -10)],
                thickness: 2.45,
                unit: unit,
                materials: materials,
                to: root
            )
            addPolyline(
                [CGPoint(x: 2, y: -3), CGPoint(x: 8, y: -10)],
                thickness: 2.45,
                unit: unit,
                materials: materials,
                to: root
            )
            addPolyline(
                [CGPoint(x: -16, y: 4), CGPoint(x: -12, y: 4)],
                thickness: 1.55,
                unit: unit,
                materials: materials,
                to: root
            )
            addPolyline(
                [CGPoint(x: -17, y: 0), CGPoint(x: -13, y: 0)],
                thickness: 1.55,
                unit: unit,
                materials: materials,
                to: root
            )
            for point in [CGPoint(x: 11, y: 6), CGPoint(x: 14, y: 1), CGPoint(x: 14, y: -5)] {
                addDisc(at: point, radius: 1.15, unit: unit, materials: materials, to: root)
            }
        }
        return VisualNode(node: root, size: CGSize(width: size, height: size * 0.80))
    }

    private static func addPolyline(
        _ points: [CGPoint],
        closed: Bool = false,
        thickness: CGFloat,
        unit: CGFloat,
        materials: [SCNMaterial],
        to root: SCNNode
    ) {
        guard points.count > 1 else { return }
        let pairs = zip(points, points.dropFirst())
        for (start, end) in pairs {
            addSegment(from: start, to: end, thickness: thickness, unit: unit, materials: materials, to: root)
        }
        if closed, let first = points.first, let last = points.last {
            addSegment(from: last, to: first, thickness: thickness, unit: unit, materials: materials, to: root)
        }
    }

    private static func addSegment(
        from start: CGPoint,
        to end: CGPoint,
        thickness: CGFloat,
        unit: CGFloat,
        materials: [SCNMaterial],
        to root: SCNNode
    ) {
        let dx = (end.x - start.x) * unit
        let dy = (end.y - start.y) * unit
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let lineWidth = thickness * unit
        let depth = max(0.82, 1.05 * unit)
        let geometry = SCNBox(
            width: length,
            height: lineWidth,
            length: depth,
            chamferRadius: min(lineWidth * 0.46, depth * 0.38)
        )
        geometry.materials = boxMaterials(materials)
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(
            Float((start.x + end.x) * unit / 2),
            Float((start.y + end.y) * unit / 2),
            Float(depth / 2)
        )
        node.eulerAngles.z = Float(atan2(dy, dx))
        root.addChildNode(node)
    }

    private static func addDisc(
        at point: CGPoint,
        radius: CGFloat,
        unit: CGFloat,
        materials: [SCNMaterial],
        to root: SCNNode
    ) {
        let depth = max(0.82, 1.05 * unit)
        let geometry = SCNCylinder(radius: radius * unit, height: depth)
        geometry.radialSegmentCount = 20
        geometry.materials = cylinderMaterials(materials)
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(Float(point.x * unit), Float(point.y * unit), Float(depth / 2))
        node.eulerAngles.x = .pi / 2
        root.addChildNode(node)
    }

    private static func boxMaterials(_ materials: [SCNMaterial]) -> [SCNMaterial] {
        let front = materials[0]
        let back = materials[1]
        let side = materials[2]
        return [front, side, back, side, side, side]
    }

    private static func cylinderMaterials(_ materials: [SCNMaterial]) -> [SCNMaterial] {
        [materials[2], materials[0], materials[1]]
    }

    private static func flagPlane(_ value: String) -> VisualNode {
        let size = CGSize(width: 27, height: 21)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            (value as NSString).draw(
                in: CGRect(x: 0, y: -1, width: size.width, height: size.height + 2),
                withAttributes: [.font: UIFont.systemFont(ofSize: 20)]
            )
        }
        let geometry = SCNPlane(width: size.width, height: size.height)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        geometry.firstMaterial = material
        return VisualNode(node: SCNNode(geometry: geometry), size: size)
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
