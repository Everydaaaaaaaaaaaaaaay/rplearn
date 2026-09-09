import XCTest

@MainActor
final class TabSceneTransitionTests: XCTestCase {
    func testRepeatedTabSelectionKeepsNativeSelectionAndSearchWorking() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "messages"
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["sceneSearch.open"].waitForExistence(timeout: 15))
        for _ in 0..<2 {
            for title in ["联系人", "首页", "我的", "信息"] {
                let tab = app.tabBars.buttons[title]
                tab.tap()
                XCTAssertTrue(tab.isSelected, "SwiftUI and the native tab controller must agree")
            }
            let open = app.buttons["sceneSearch.open"]
            XCTAssertTrue(open.waitForExistence(timeout: 3))
            open.tap()
            XCTAssertTrue(app.textFields["sceneSearch.field"].waitForExistence(timeout: 3))
            app.buttons["sceneSearch.close"].tap()
            XCTAssertTrue(open.waitForExistence(timeout: 3))
        }
    }
}
