import XCTest
import UIKit

/// Each attachment is a product screenshot; image composition is reviewed separately.
@MainActor
final class CityTabSceneTests: XCTestCase {
    func testAllCityBackgroundsAndSearch() {
        continueAfterFailure = false
        let cities = ["london", "melbourne", "newyork", "capetown", "singapore",
                      "dublin", "edinburgh", "vancouver", "auckland", "nairobi",
                      "toronto", "sydney", "neworleans", "manchester", "kingston"]
        for city in cities {
            let app = XCUIApplication()
            app.launchEnvironment = [
                "UI_TEST_SKIP_ONBOARDING": "1",
                "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
                "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
                "UI_TEST_CITY_TAB_REGION": city,
                "UI_TEST_TAB": "messages"
            ]
            app.launch()
            for (role, title) in [("messages", "信息"), ("contacts", "联系人")] {
                let tab = app.tabBars.buttons[title]
                XCTAssertTrue(tab.waitForExistence(timeout: 15))
                if !tab.isSelected { tab.tap() }
                XCTAssertTrue(tab.isSelected)
                let open = app.buttons["sceneSearch.open"]
                XCTAssertTrue(open.waitForExistence(timeout: 10))
                // An active search confirms that the screen has finished entering and remains usable.
                open.tap()
                XCTAssertTrue(app.textFields["sceneSearch.field"].waitForExistence(timeout: 5))
                app.buttons["sceneSearch.close"].tap()
                XCTAssertTrue(app.textFields["sceneSearch.field"].waitForNonExistence(timeout: 5))
                XCTAssertTrue(open.waitForExistence(timeout: 5))
                let screenshot = app.screenshot()
                XCTAssertTrue(Self.hasSceneDetail(screenshot.image), "Reject an unrendered background")
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "city-tab-\(city)-\(role)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            app.terminate()
        }
    }

    private static func hasSceneDetail(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage,
              let crop = cg.cropping(to: CGRect(x: 0, y: CGFloat(cg.height) * 0.45,
                                               width: CGFloat(cg.width),
                                               height: CGFloat(cg.height) * 0.3)) else { return false }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 32, height: 32,
                                          bitsPerComponent: 8, bytesPerRow: 128,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return true
        }
        guard drawn else { return false }
        let brightness = stride(from: 0, to: pixels.count, by: 4).map {
            (Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])) / 3
        }
        return (brightness.max() ?? 0) - (brightness.min() ?? 0) > 25
    }
}
