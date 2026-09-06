import XCTest

@MainActor
final class ActivitySceneTests: XCTestCase {
    private func launch(accelerated: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_HOME_DESTINATION"] = "activities"
        app.launchEnvironment["UI_TEST_ACTIVITY_NAMESPACE"] = UUID().uuidString
        if accelerated { app.launchEnvironment["UI_TEST_ACTIVITY_CADENCE"] = "accelerated" }
        app.launch()
        XCTAssertTrue(app.buttons["activities.tab.park"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["activities.scenePreview"].exists)
        return app
    }
    private func attach(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
    private func edgeBack(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
    }
    private func tap(_ id: String, app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        if !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        button.tap()
    }

    func testScenesActionsJournalAndBothBackLevels() {
        let app = launch()
        defer { app.terminate() }
        attach("production-park", app: app)
        tap("activities.scene.walk", app: app)
        XCTAssertTrue(app.buttons["activities.action.start"].waitForExistence(timeout: 4))
        attach("action-introduction", app: app)
        edgeBack(app)
        XCTAssertTrue(app.buttons["activities.tab.pond"].waitForExistence(timeout: 4))
        // Horizontal swiping belongs to the scene strip, not the back edge.
        app.scrollViews["activities.sceneStrip"].swipeLeft()
        XCTAssertTrue(app.buttons["activities.scene.sketch"].waitForExistence(timeout: 4))
        attach("production-pond", app: app)
        tap("activities.scene.postcard", app: app)
        tap("activities.action.start", app: app)
        tap("activities.choice.0", app: app)
        XCTAssertTrue(app.staticTexts["activities.action.feedback"].exists)
        attach("action-choice-feedback", app: app)
        tap("activities.action.next", app: app)
        tap("activities.choice.1", app: app)
        tap("activities.action.next", app: app)
        attach("action-summary", app: app)
        tap("activities.action.finish", app: app)
        XCTAssertTrue(app.staticTexts["activities.action.saved"].waitForExistence(timeout: 3))
        tap("activities.action.return", app: app)
        tap("activities.journal", app: app)
        XCTAssertTrue(app.navigationBars["行动足迹"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["I found a quiet spot by the pond."].firstMatch.exists)
        attach("action-journal", app: app)
        app.buttons["完成"].tap()
        tap("activities.tab.park", app: app)
        XCTAssertTrue(app.buttons["activities.scene.coffee"].exists)
        tap("activities.scene.coffee", app: app)
        tap("activities.action.back", app: app)
        tap("activities.scene.journal", app: app)
        tap("activities.action.back", app: app)
        tap("activities.tab.pond", app: app)
        tap("activities.scene.observe", app: app)
        tap("activities.action.back", app: app)
        tap("activities.scene.sketch", app: app)
        tap("activities.action.back", app: app)
        edgeBack(app)
        XCTAssertTrue(app.buttons["城市活动"].waitForExistence(timeout: 4))
    }

    func testProductionCooldownSurvivesPauseAndResume() {
        let app = launch()
        defer { app.terminate() }
        let motion = app.buttons["activities.motion"]
        let quiet = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (motion.value as? String ?? "").contains("自然空场")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [quiet], timeout: 15), .completed)
        motion.tap()
        XCTAssertEqual(motion.value as? String, "静态")
        motion.tap()
        let unexpectedRestart = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !(motion.value as? String ?? "").contains("自然空场")
        }, object: nil)
        unexpectedRestart.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedRestart], timeout: 10), .completed)
    }

    func testPondLoopStaticFallbackAndTabLifecycle() {
        let app = launch()
        defer { app.terminate() }
        tap("activities.tab.pond", app: app)
        let motion = app.buttons["activities.motion"]
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (motion.value as? String ?? "").contains("播放中")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 5), .completed)
        // Cross the 18-second AVPlayerLooper boundary; this must not enter a
        // runner's quiet interval or stop the decoder at a notification seek.
        let stalled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !(motion.value as? String ?? "").contains("播放中")
        }, object: nil)
        stalled.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [stalled], timeout: 21), .completed)
        motion.tap()
        XCTAssertEqual(motion.value as? String, "静态")
        attach("pond-static-fallback", app: app)
        motion.tap()
        app.tabBars.buttons["我的"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.buttons["activities.scene.observe"].waitForExistence(timeout: 4))
    }
}
