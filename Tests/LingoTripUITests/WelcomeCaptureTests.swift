import XCTest

/// Assets are captured from product screens with an isolated in-memory account.
@MainActor
final class WelcomeCaptureTests: XCTestCase {
    func testCaptureProductScreens() {
        continueAfterFailure = false
        let original = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = original }
        for (appearance, suffix) in [(XCUIDevice.Appearance.light, "light"), (.dark, "dark")] {
            XCUIDevice.shared.appearance = appearance
            let app = XCUIApplication()
            app.launchEnvironment = [
                "UI_TEST_SKIP_ONBOARDING": "1",
                "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
                "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
                "UI_TEST_WELCOME_CAPTURE": "1",
                "UI_TEST_TAB": "contacts"
            ]
            app.launch()
            let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby")).firstMatch
            XCTAssertTrue(ruby.waitForExistence(timeout: 20))
            ruby.tap()
            let message = app.buttons["发消息"]
            XCTAssertTrue(message.waitForExistence(timeout: 5))
            message.tap()
            XCTAssertTrue(app.descendants(matching: .any)["chat.composer"].firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "cosy")).firstMatch.waitForExistence(timeout: 5))
            capture("welcome-chat-\(suffix)", app)
            let cosy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "cosy")).firstMatch
            XCTAssertTrue(cosy.waitForExistence(timeout: 5), app.debugDescription)
            cosy.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "舒适")).firstMatch.waitForExistence(timeout: 8), app.debugDescription)
            capture("welcome-dictionary-\(suffix)", app)
            app.terminate()
            app.launchEnvironment["UI_TEST_TAB"] = "home"
            app.launchEnvironment["UI_TEST_HOME_DESTINATION"] = "activities"
            app.launchEnvironment["UI_TEST_SOCIAL_FIXTURE"] = "1"
            app.launchEnvironment["UI_TEST_ACTIVITY_NAMESPACE"] = UUID().uuidString
            app.launch()
            XCTAssertTrue(app.buttons["activities.tab.park"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["activities.scene.park-seat"].waitForExistence(timeout: 8))
            capture("welcome-activity-\(suffix)", app)
            app.terminate()
            app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "0"
            app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "0"
            app.launchEnvironment["UI_TEST_ONBOARDING_SELECTION"] = "1"
            app.launch()
            XCTAssertTrue(app.buttons["onboarding.selection.confirm"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.descendants(matching: .any)["onboarding.character.avatar.london"].firstMatch.waitForExistence(timeout: 5))
            capture("welcome-companion-\(suffix)", app)
            app.terminate()
        }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
