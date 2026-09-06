import XCTest
import SwiftUI
import UIKit
@testable import HomeFeature

final class ActivitySceneGeometryTests: XCTestCase {
    @MainActor
    func testGlowingLabelInkSharesPlainTextLayoutCentre() throws {
        let styled = ImageRenderer(content: ActivitySceneLabel(title: "城市漫步")
            .frame(width: 128, height: 60).background(.black))
        let plain = ImageRenderer(content: Text("城市漫步")
            .font(.system(size: 22, weight: .bold, design: .rounded)).tracking(-0.45)
            .foregroundStyle(.white).frame(width: 128, height: 60).background(.black))
        styled.scale = 3
        plain.scale = 3
        let actual = try XCTUnwrap(styled.uiImage)
        let expected = try XCTUnwrap(plain.uiImage)
        for (name, image) in [("glowing-label", actual), ("plain-label", expected)] {
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let actualBounds = try coreBounds(actual)
        let expectedBounds = try coreBounds(expected)
        XCTAssertEqual(actualBounds.midX, expectedBounds.midX, accuracy: 3)
        XCTAssertEqual(actualBounds.midY, expectedBounds.midY, accuracy: 3)
    }

    private func coreBounds(_ image: UIImage) throws -> CGRect {
        let cg = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        var minX = cg.width, minY = cg.height, maxX = 0, maxY = 0
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let i = (y * cg.width + x) * 4
                if pixels[i] > 247 && pixels[i + 1] > 239 && pixels[i + 2] > 218 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        XCTAssertLessThan(minX, maxX)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func testProjectionMapsAllFourCornersAndSharedCentre() {
        for anchor in ActivitySceneAnchor.allCases {
            let quad = anchor.localQuad(scale: 402.0 / 852)
            let h = HomeHomography(quad: quad)
            let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
            for (input, expected) in zip(corners, quad.points) {
                let result = h.project(input)
                XCTAssertEqual(result.x, expected.x, accuracy: 0.001)
                XCTAssertEqual(result.y, expected.y, accuracy: 0.001)
            }
            let centre = CGPoint(x: 0.5, y: 0.5)
            let recovered = h.inverted!.project(h.project(centre))
            XCTAssertEqual(recovered.x, centre.x, accuracy: 0.001)
            XCTAssertEqual(recovered.y, centre.y, accuracy: 0.001)
        }
        XCTAssertGreaterThan(ActivitySceneAnchor.map.bounds.width, ActivitySceneAnchor.journal.bounds.width)
        XCTAssertGreaterThan(ActivitySceneAnchor.journal.bounds.width, ActivitySceneAnchor.cup.bounds.width)
    }

    func testCadenceHasCooldownAndAvoidsNearlyEqualIntervals() {
        struct Seeded: RandomNumberGenerator {
            var state: UInt64 = 57
            mutating func next() -> UInt64 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return state
            }
        }
        var generator = Seeded()
        var cadence = ActivityAmbientCadence()
        var previous: TimeInterval?
        var draws: [TimeInterval] = []
        for _ in 0..<200 {
            let delay = cadence.nextDelay(using: &generator)
            XCTAssertTrue((24...95).contains(delay))
            if let previous { XCTAssertGreaterThanOrEqual(abs(delay - previous), 8) }
            previous = delay
            draws.append(delay)
        }
        XCTAssertTrue(draws.contains { $0 > 70 })
        XCTAssertTrue(draws.contains { $0 < 40 })
    }
}
