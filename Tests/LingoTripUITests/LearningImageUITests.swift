import XCTest

/// 工程图形只验证加载、重试与选择，不代表正式低年级教材内容。
@MainActor
final class LearningImageUITests: XCTestCase {
    func testImageFailureRetryAndChoice() throws {
        let app = launch(kind: "choice", failure: true)
        let check = app.buttons["检查"]
        XCTAssertTrue(app.buttons["重新载入"].waitForExistence(timeout: 10))
        XCTAssertFalse(check.isEnabled)
        XCTAssertFalse(app.buttons["learning.option.a"].isEnabled)
        XCTAssertTrue(app.buttons["暂时跳过，留待补答"].isEnabled)
        app.buttons["重新载入"].tap()
        let red = app.buttons["learning.option.a"]
        XCTAssertTrue(red.waitForExistence(timeout: 10))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: red)], timeout: 10) == .completed)
        red.tap()
        XCTAssertTrue(red.isSelected)
        XCTAssertTrue(check.isEnabled)
        XCTAssertFalse(app.staticTexts["红色圆形"].exists)
        capture(app, name: "图片选择-重试成功")
    }
    func testImageMatchingLargeTextDark() throws {
        let app = launch(kind: "matching", large: true)
        for (left, right) in [("红色圆形", "圆形"), ("蓝色方形", "方形")] {
            let lhs = app.buttons[left]; reveal(lhs, in: app); lhs.tap()
            let rhs = app.buttons[right]; reveal(rhs, in: app); rhs.tap()
        }
        XCTAssertTrue(app.buttons["检查"].isEnabled)
        capture(app, name: "图片配对-最大字号深色")
    }
    private func launch(kind: String, failure: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
            "UI_TEST_LEARNING_QUESTION": kind, "UI_TEST_LEARNING_IMAGES": "1"]
        if failure { app.launchEnvironment["UI_TEST_LEARNING_IMAGE_FAILURE"] = "1" }
        if large {
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
        }
        app.launch()
        XCTAssertTrue(app.buttons["退出挑战"].waitForExistence(timeout: 15))
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            let top = app.buttons["退出挑战"].frame.maxY + 12
            let bottom = app.buttons["检查"].frame.minY - 16
            if element.isHittable, element.frame.midY >= top, element.frame.midY <= bottom { return }
            let down = element.exists && element.frame.midY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (bottom - top) * (down ? 0.2 : 0.8)))
            let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (bottom - top) * (down ? 0.8 : 0.2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
