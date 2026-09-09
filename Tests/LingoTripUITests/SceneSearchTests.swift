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

        let open = app.buttons["sceneSearch.open"]
        let close = app.buttons["sceneSearch.close"]
        let field = app.textFields["sceneSearch.field"]
        for _ in 0..<3 {
            XCTAssertTrue(open.waitForExistence(timeout: 15))
            XCTAssertLessThanOrEqual(open.frame.width, 60, "Collapsed search must remain circular")
            open.tap()
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            XCTAssertTrue(close.isHittable)
            field.typeText("Oliver")
            app.buttons["sceneSearch.dismissKeyboard"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
            XCTAssertTrue(field.exists, "Dismissing the keyboard preserves search")
            XCTAssertEqual(field.value as? String, "Oliver")
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            close.tap()
            XCTAssertTrue(field.waitForNonExistence(timeout: 3))
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        }
        XCTAssertTrue(open.isHittable)
        XCTAssertLessThanOrEqual(open.frame.width, 60)
    }
}
