import XCTest

@MainActor
final class SceneDragMotionUITests: XCTestCase {
    func testSceneDragsReturnAndPreserveNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "home"
        app.launch()
        defer { app.terminate() }

        for (tab, entryName) in [("活动", "世界地图"), ("我的", "设置，AI、语音与偏好")] {
            app.tabBars.buttons[tab].tap()
            let entry = app.buttons[entryName]
            XCTAssertTrue(entry.waitForExistence(timeout: 15))
            for target in [CGVector(dx: 0.8, dy: 0.7), CGVector(dx: 0.15, dy: 0.25)] {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                    .press(forDuration: 0.05,
                           thenDragTo: app.coordinate(withNormalizedOffset: target),
                           withVelocity: .slow, thenHoldForDuration: 0.5)
                XCTAssertTrue(entry.isHittable, "拖动不应误触入口，回弹后仍能点击")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(tab)拖动回弹后"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            entry.tap()
            let back = tab == "活动" ? app.buttons["返回首页"] : app.navigationBars["设置"].buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5), "拖动后仍应正常进入二级页面")
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(back.waitForNonExistence(timeout: 5))
            XCTAssertTrue(entry.isHittable)
        }
    }
}
