import XCTest

@MainActor
final class ProfileAvatarTests: XCTestCase {
    func testAccountOffersPhotoPicker() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "me"
        app.launch()
        defer { app.terminate() }
        let account = app.buttons["账号与订阅"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        let picker = app.buttons["profile.avatarPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.isEnabled)
        let accountImage = XCTAttachment(screenshot: app.screenshot())
        accountImage.name = "Account avatar entry"
        accountImage.lifetime = .keepAlways
        add(accountImage)
        picker.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let photosImage = XCTAttachment(screenshot: app.screenshot())
        photosImage.name = "System photo picker"
        photosImage.lifetime = .keepAlways
        add(photosImage)
        cancel.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
    }
}
