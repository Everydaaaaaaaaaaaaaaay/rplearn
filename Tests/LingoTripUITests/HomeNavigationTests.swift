import XCTest

@MainActor
final class HomeNavigationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "home"
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testMapQuickTapCompletesFeedbackBeforeTransition() {
        app.launch()
        let mapEntry = app.buttons["世界地图"]
        XCTAssertTrue(mapEntry.waitForExistence(timeout: 5))

        let start = ContinuousClock.now
        mapEntry.tap()
        XCTAssertTrue(app.buttons["返回首页"].waitForExistence(timeout: 2))
        let elapsed = ContinuousClock.now - start

        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(100))
        let overview = app.buttons["回到地球全景"]
        XCTAssertTrue(overview.exists)
        app.swipeLeft()
        overview.tap()
        // Allow the native camera transition and globe tiles to settle before visual capture.
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "world-globe-overview"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testMapSupportsLeadingEdgeSwipeBack() {
        app.launch()
        let mapEntry = app.buttons["世界地图"]
        XCTAssertTrue(mapEntry.waitForExistence(timeout: 5))
        mapEntry.tap()
        XCTAssertTrue(app.buttons["返回首页"].waitForExistence(timeout: 2))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(mapEntry.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["返回首页"].exists)
    }
}
