import XCTest

@MainActor
final class SceneSearchTests: XCTestCase {
    func testMessagesSearchCanReopenAndDismissKeyboard() {
        verifySearch(tab: "messages")
    }

    func testContactsSearchCanReopenAndDismissKeyboard() {
        verifySearch(tab: "contacts")
    }

    private func verifySearch(tab: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = tab
        app.launch()
        defer { app.terminate() }

        let field = app.textFields["sceneSearch.field"]
        for _ in 0..<3 {
            XCTAssertTrue(field.waitForExistence(timeout: 15))
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            field.typeText("Oliver")
            app.buttons["sceneSearch.dismissKeyboard"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
            XCTAssertTrue(field.exists, "收起键盘应保留搜索框")
            XCTAssertEqual(field.value as? String, "Oliver")
            app.buttons["sceneSearch.clear"].tap()
            XCTAssertTrue(field.exists)
        }
        XCTAssertTrue(field.isHittable)
    }
}
