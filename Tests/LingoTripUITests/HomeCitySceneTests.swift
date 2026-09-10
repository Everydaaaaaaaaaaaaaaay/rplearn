import XCTest
import UIKit

@MainActor
final class HomeCitySceneTests: XCTestCase {
    func testLondon() { verifyScene("london", city: "伦敦") }
    func testMelbourne() { verifyScene("melbourne", city: "墨尔本") }
    func testNewyork() { verifyScene("newyork", city: "纽约") }
    func testCapetown() { verifyScene("capetown", city: "开普敦") }
    func testSingapore() { verifyScene("singapore", city: "新加坡") }
    func testDublin() { verifyScene("dublin", city: "都柏林") }
    func testEdinburgh() { verifyScene("edinburgh", city: "爱丁堡") }
    func testVancouver() { verifyScene("vancouver", city: "温哥华") }
    func testAuckland() { verifyScene("auckland", city: "奥克兰") }
    func testNairobi() { verifyScene("nairobi", city: "内罗毕") }
    func testToronto() { verifyScene("toronto", city: "多伦多") }
    func testSydney() { verifyScene("sydney", city: "悉尼") }
    func testNeworleans() { verifyScene("neworleans", city: "新奥尔良") }
    func testManchester() { verifyScene("manchester", city: "曼彻斯特") }
    func testKingston() { verifyScene("kingston", city: "金斯敦") }

    func testLondonEntryEdgesAndResume() {
        verifyScene("london", city: "伦敦", exerciseEdges: true)
    }

    private func verifyScene(_ id: String, city: String, exerciseEdges: Bool = false) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "home"
        app.launchEnvironment["UI_TEST_REGION"] = id
        app.launch()
        defer { app.terminate() }
        let map = app.buttons["世界地图"]
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        XCTAssertTrue(map.isHittable)
        XCTAssertTrue(app.buttons["城市活动"].isHittable)
        let story = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "剧情，")).firstMatch
        XCTAssertTrue(story.isHittable)
        let location = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "当前驻地，", city)
        ).firstMatch
        XCTAssertTrue(location.exists, "城市名称必须与背景同步更新")
        if exerciseEdges {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(map.waitForExistence(timeout: 10))
        }
        func openEntry(_ element: XCUIElement) {
            if exerciseEdges {
                // 正视伦敦入口左边内侧 8pt，检验热区边缘而非仅点击视觉中心。
                element.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
                    .withOffset(CGVector(dx: 8, dy: 0)).press(forDuration: 0.12)
            } else {
                element.tap()
            }
        }
        // 可访问树先于首个合成帧就绪，直接截图偶尔只得到启动底色。
        // 检查内容区域的像素差异，而非增加一个与机器速度有关的固定 sleep。
        var renderedScreenshot: XCUIScreenshot?
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let candidate = app.screenshot()
            guard Self.hasRenderedScene(candidate.image) else { return false }
            renderedScreenshot = candidate
            return true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 10), .completed,
                       "场景尚未实际呈现，不接受空白验收截图")
        guard let renderedScreenshot else { return }
        let screenshot = XCTAttachment(screenshot: renderedScreenshot)
        screenshot.name = "home-city-\(id)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        openEntry(map)
        let back = app.buttons["返回首页"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 4))

        // 每城重做背景后，三个入口都必须实际点击，不能以代表城市代替新锚点验收。
        openEntry(story)
        XCTAssertTrue(app.navigationBars["剧情"].waitForExistence(timeout: 4))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 4))
        openEntry(app.buttons["城市活动"])
        let activitiesBack = app.buttons["activities.back"]
        XCTAssertTrue(activitiesBack.waitForExistence(timeout: 4))
        activitiesBack.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 4))
    }

    private static func hasRenderedScene(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage,
              let crop = cg.cropping(to: CGRect(x: CGFloat(cg.width) * 0.08,
                                               y: CGFloat(cg.height) * 0.15,
                                               width: CGFloat(cg.width) * 0.84,
                                               height: CGFloat(cg.height) * 0.65)) else { return false }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16,
                bitsPerComponent: 8, bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return true
        }
        guard didDraw else { return false }
        let brightness = stride(from: 0, to: pixels.count, by: 4).map {
            (Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])) / 3
        }
        // 忽略状态栏/底栏；大面积均匀底色不能作为场景截图通过。
        return (brightness.max() ?? 0) - (brightness.min() ?? 0) > 40
    }
}
