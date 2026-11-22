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
        app.launchEnvironment["UI_TEST_CITY_TAB_REGION"] = "london"
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

    /// 票根夹经缩放转场从地图进入。中途取消的返回手势（左缘短拖、顶部下拉）不能把顶栏和返回按钮弄丢。
    func testTicketStubsKeepHeaderAfterCancelledSwipeBack() {
        app.launch()
        let mapEntry = app.buttons["世界地图"]
        XCTAssertTrue(mapEntry.waitForExistence(timeout: 5))
        mapEntry.tap()
        let stubsEntry = app.buttons["票根夹"]
        XCTAssertTrue(stubsEntry.waitForExistence(timeout: 5))
        stubsEntry.tap()
        let back = app.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label == '返回'")).firstMatch
        let title = app.staticTexts["票根夹"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(title.exists)
        for _ in 0..<2 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
            XCTAssertTrue(back.waitForExistence(timeout: 3) && back.isHittable, "取消返回后返回按钮应还在")
            XCTAssertTrue(title.exists, "取消返回后标题应还在")
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(back.waitForExistence(timeout: 3) && back.isHittable, "下拉取消后返回按钮应还在")
        XCTAssertTrue(title.exists)
        back.tap()
        XCTAssertTrue(stubsEntry.waitForExistence(timeout: 5))
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
