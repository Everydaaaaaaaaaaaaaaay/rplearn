// Compile with HomeDepartureSceneSupport.swift and HomeCityScenes.swift.
// Diagnostic overlays only; never re-encode or replace production assets.
import AppKit
import CryptoKit

@main
enum HomeScenePerspectiveAudit {
    struct Landmarks: Decodable {
        let cities: [City]
        struct City: Decodable {
            let id: String
            let size: [Int]
            let mapFrame: [CGFloat]
            let otherSurfaces: [String: [CGFloat]]?
            let sha256: String
        }
    }

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let landmarks = try JSONDecoder().decode(Landmarks.self, from: Data(contentsOf:
            root.appendingPathComponent("Assets/HomeScenes/perspective-landmarks.json")))
        precondition(Set(landmarks.cities.map(\.id)) == Set(HomeDepartureSceneLayout.scenes.keys))
        let output = root.appendingPathComponent("build/HomePerspectiveAudit")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (id, layout) in HomeDepartureSceneLayout.scenes.sorted(by: { $0.key < $1.key }) {
            let path = root.appendingPathComponent("App/Assets.xcassets/\(layout.assetName).imageset/\(layout.assetName).jpg")
            let data = try Data(contentsOf: path)
            let witness = landmarks.cities.first { $0.id == id }!
            precondition(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == witness.sha256,
                         "\(id): asset changed; repeat pixel measurement and visual acceptance")
            guard let original = NSBitmapImageRep(data: data),
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: original.pixelsWide, pixelsHigh: original.pixelsHigh,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError(id) }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let width = CGFloat(original.pixelsWide), height = CGFloat(original.pixelsHigh)
            precondition(witness.size == [original.pixelsWide, original.pixelsHigh])
            func verify(_ entry: HomeDepartureHotspotLayout, pixels: [CGFloat]) {
                for (i, p) in entry.projectedRegion().surface.quad.points.enumerated() {
                    precondition(abs(p.x * width - pixels[2 * i]) < 0.01 &&
                                 abs(p.y * height - pixels[2 * i + 1]) < 0.01,
                                 "\(id): code no longer matches accepted pixel landmarks")
                }
            }
            verify(layout.map, pixels: witness.mapFrame)
            verify(layout.story, pixels: witness.mapFrame)
            for (name, pixels) in witness.otherSurfaces ?? [:] {
                verify(name == "location" ? layout.location : layout.activities, pixels: pixels)
            }
            original.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * width, y: (1 - p.y) * height) }
            func line(_ points: [CGPoint], color: NSColor, close: Bool = false) {
                let path = NSBezierPath()
                path.move(to: point(points[0]))
                for p in points.dropFirst() { path.line(to: point(p)) }
                if close { path.close() }
                color.setStroke()
                path.lineWidth = 2
                path.stroke()
            }
            let wall = layout.map.projectedRegion().surface
            line(wall.quad.points, color: .cyan, close: true)
            for t in [0.25, 0.5, 0.75] {
                line([wall.homography.project(CGPoint(x: 0, y: t)), wall.homography.project(CGPoint(x: 1, y: t))], color: .cyan)
                line([wall.homography.project(CGPoint(x: t, y: 0)), wall.homography.project(CGPoint(x: t, y: 1))], color: .cyan)
            }
            for entry in [layout.location, layout.map, layout.story, layout.activities] {
                let region = entry.projectedRegion()
                for p in region.photoQuad.points + entry.projectedRegion(size: entry.hitSize).photoQuad.points {
                    precondition(p.x >= 0 && p.x <= 1 && p.y > 0.07 &&
                                 p.y * HomeDepartureCanvas.height <= HomeDepartureCanvas.interactiveContentBottom,
                                 "\(id): projected entry leaves safe area: \(p)")
                    for viewport in [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852),
                                     CGSize(width: 402, height: 874), CGSize(width: 440, height: 956)] {
                        let placement = HomeDepartureCanvas.placement(in: viewport)
                        let x = p.x * HomeDepartureCanvas.width * placement.scale + placement.horizontalInset
                        let y = p.y * placement.height * placement.scale
                        precondition(x >= 0 && x <= viewport.width && y >= 40 && y <= viewport.height - 84,
                                     "\(id): projected entry clipped at \(viewport)")
                    }
                }
                line(region.photoQuad.points, color: .yellow, close: true)
                let c = region.planeCenter, size = region.planeSize
                line([region.surface.homography.project(CGPoint(x: c.x - size.width / 2, y: c.y)),
                      region.surface.homography.project(CGPoint(x: c.x + size.width / 2, y: c.y))], color: .magenta)
            }
            (id + " | cyan: map frame/grid; yellow: entry; magenta: baseline" as NSString).draw(
                at: CGPoint(x: 14, y: height - 45),
                withAttributes: [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: NSColor.white,
                                 .backgroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(id).png"))
        }
        print("15 assets: hashes, pixel landmarks and code agree. Inspect overlays separately; numerical agreement is NOT visual approval.")
    }
}
