import XCTest

@MainActor
final class AdultLifeStoryTests: XCTestCase {
    func testNewEditionDeclineAndResume() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_TAB": "home", "UI_TEST_LONDON_EPISODE": "1",
            "UI_TEST_DEPARTURE_RESOURCE": "departures_mainline_melbourne_v1",
            "UI_TEST_PERSISTENCE_NAMESPACE": UUID().uuidString,
            "UI_TEST_EPISODE_AUDIO": "0", "UI_TEST_EPISODE_FRESH": "1",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["咖啡馆门外，一阵电车铃声渐渐远去。"].exists)
        func reachChoice() {
            for _ in 0..<35 {
                if app.buttons["episode.choice.b"].exists { return }
                let next = app.buttons["episode.next"]
                XCTAssertTrue(next.waitForExistence(timeout: 5))
                next.tap()
            }
            XCTFail("Did not reach an actual choice")
        }
        reachChoice()
        app.buttons["episode.choice.b"].tap()
        let node = NSPredicate(format: "value CONTAINS %@", "node:RB20_01;")
        expectation(for: node, evaluatedWith: app.buttons["episode.sound"])
        waitForExpectations(timeout: 10)
        app.terminate()
        app.launchEnvironment["UI_TEST_EPISODE_FRESH"] = "0"
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 20))
        XCTAssertTrue((app.buttons["episode.sound"].value as? String ?? "").contains("node:RB20_01;"))
        reachChoice()
        app.buttons["episode.choice.b"].tap()
        for _ in 0..<20 {
            if app.buttons["episode.finish"].exists { break }
            let next = app.buttons["episode.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        XCTAssertTrue(app.buttons["episode.finish"].exists)
        XCTAssertTrue(app.staticTexts["本章影响：这次没有定下新的散步日期。"].exists)
        app.buttons["episode.history"].tap()
        XCTAssertTrue(app.buttons["继续阅读"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["可以是对鱼充满热情，也可以是对吐司。"].exists)
        app.buttons["继续阅读"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "adult-life-ruby-decline-ending"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
