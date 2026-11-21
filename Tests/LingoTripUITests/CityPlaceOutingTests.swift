import XCTest

@MainActor
final class CityPlaceOutingTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "UI_TEST_TAB": "places-preview",
            "UI_TEST_OUTING_AUDIO": "0", "UI_TEST_ACTIVITY_NAMESPACE": UUID().uuidString,
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
        ]
    }
    override func tearDown() async throws { app.terminate() }
    private func screenshot(_ name: String) {
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
    /// 账号激活会把活动导航重置到首页，预览启动后从“出去走走”进入地点页。
    private func openPlaces() {
        let entrance = app.buttons["home.activities"]
        XCTAssertTrue(entrance.waitForExistence(timeout: 20))
        entrance.tap()
    }
    private func reveal(_ id: String) {
        for _ in 0..<10 {
            if app.buttons[id].exists { return }
            let next = app.buttons["activities.action.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 4))
            if !next.isHittable { app.swipeUp() }
            next.tap()
        }
        XCTFail("Missing outing control: \(id)")
    }
    func testActualBranchSurvivesPauseRelaunchAndAppearsInJournal() {
        app.launch()
        openPlaces()
        let cafe = app.buttons["activities.place.london-bloomsbury-cafe"]
        XCTAssertTrue(cafe.waitForExistence(timeout: 20))
        screenshot("places-list-standard")
        cafe.tap()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 10))
        app.buttons["显示中文对照"].tap()
        screenshot("places-opening")
        reveal("activities.choice.1")
        app.buttons["activities.choice.1"].tap()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 4))
        app.buttons["activities.action.back"].tap()
        let resume = app.buttons["activities.resumePlaceOuting"]
        XCTAssertTrue(resume.waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["activities.place.london-bloomsbury-cafe"].exists)
        screenshot("places-resume")
        resume.tap()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        openPlaces()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 20))
        reveal("activities.choice.1")
        app.buttons["activities.choice.1"].tap()
        reveal("activities.action.finish")
        XCTAssertTrue(app.buttons["activities.encounter.addFriend"].isEnabled)
        screenshot("places-ending")
        app.buttons["activities.action.finish"].tap()
        XCTAssertTrue(app.buttons["activities.scene.more"].waitForExistence(timeout: 5))
        app.buttons["activities.scene.more"].tap()
        app.buttons["足迹"].tap()
        XCTAssertTrue(app.staticTexts["一张暂时空着的凳子"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["与 Alex Rowan 的这次交流"].exists)
        screenshot("places-journal")
    }
    func testLargeTextFindsThirdPlaceAndSolitudeEnding() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openPlaces()
        XCTAssertTrue(app.buttons["activities.place.london-bloomsbury-cafe"].waitForExistence(timeout: 20))
        let park = app.buttons["activities.place.london-primrose-hill"]
        for _ in 0..<2 { app.buttons["activities.scene.next"].tap() }
        XCTAssertTrue(park.isHittable)
        screenshot("places-third-place-large")
        park.tap()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 8))
        app.buttons["显示中文对照"].tap()
        XCTAssertTrue(app.staticTexts["你在这里待了一阵，却没有与谁交谈。"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["独处片刻"].exists)
        for _ in 0..<5 where !app.buttons["activities.action.next"].isHittable { app.swipeUp() }
        app.buttons["activities.action.next"].tap()
        XCTAssertTrue(app.buttons["activities.action.finish"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activities.encounter.addFriend"].exists)
        screenshot("places-solitude-large")
    }
}
