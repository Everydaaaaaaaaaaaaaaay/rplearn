import XCTest

@MainActor
final class DepartureCollectionTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "home"
        app.launchEnvironment["UI_TEST_LONDON_EPISODE"] = "1"
        app.launchEnvironment["UI_TEST_EPISODE_FRESH"] = "1"
        app.launchEnvironment["UI_TEST_EPISODE_AUDIO"] = "1"
    }
    override func tearDown() async throws { app.terminate() }

    private func valueContains(_ text: String, timeout: TimeInterval = 15) {
        let sound = app.buttons["episode.sound"]
        expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: sound)
        waitForExpectations(timeout: timeout)
    }

    func testNewMainlinePreparedAudioAndBranchResume() {
        app.launchEnvironment["UI_TEST_DEPARTURE_RESOURCE"] = "departures_mainline_newyork_v1"
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 20))
        valueContains("prepared:true")
        valueContains("completed:arrival;")
        // Rapid manual advance cancels old clips and stops at a real choice.
        for _ in 0..<20 {
            if app.buttons["episode.choice.a"].exists { break }
            app.buttons["episode.next"].tap()
        }
        XCTAssertTrue(app.buttons["episode.choice.a"].exists)
        app.buttons["episode.choice.a"].tap()
        valueContains("node:reply_a;")
        app.terminate()
        app.launchEnvironment["UI_TEST_EPISODE_FRESH"] = "0"
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 20))
        valueContains("node:reply_a;")
        XCTAssertTrue(app.staticTexts["你可以舍不得那张照片，也可以先发出那两个词。"].exists)
        for _ in 0..<45 {
            if app.buttons["episode.restart"].exists { break }
            if app.buttons["episode.choice.b"].exists { app.buttons["episode.choice.b"].tap() }
            else { app.buttons["episode.next"].tap() }
        }
        XCTAssertTrue(app.buttons["episode.restart"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "departures-newyork-ending"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testCityPreparedNarrationLookupAndTranslation() {
        app.launchEnvironment["UI_TEST_DEPARTURE_RESOURCE"] = "departures_city_manchester_v1"
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 20))
        valueContains("prepared:true")
        valueContains("completed:arrival;")
        let translation = app.buttons["episode.translation"]
        translation.tap()
        XCTAssertFalse(app.staticTexts["Leah 给你在试听桌留了十分钟。"].exists)
        translation.tap()
        let word = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "minutes\\s*" )).firstMatch
        XCTAssertTrue(word.exists); word.tap()
        XCTAssertTrue(app.buttons["播放读音"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.24)).tap()
        XCTAssertFalse(app.buttons["播放读音"].exists)
        valueContains("completed:arrival;")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "departures-manchester-reading"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["episode.close"].tap()
    }
}
