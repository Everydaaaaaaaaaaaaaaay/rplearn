import XCTest

@MainActor
final class LaunchPerformanceTests: XCTestCase {
    func testLaunchToInteractiveMessages() {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "messages"
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(), XCTClockMetric()], options: options) {
            app.launch()
            let search = app.buttons["sceneSearch.open"]
            XCTAssertTrue(search.waitForExistence(timeout: 15))
            XCTAssertTrue(search.isHittable)
        }
        app.terminate()
    }
}
