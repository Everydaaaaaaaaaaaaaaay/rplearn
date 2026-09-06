import XCTest

@MainActor
final class ActivitySceneTests: XCTestCase {
    private func launch(accelerated: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_HOME_DESTINATION"] = "activities"
        app.launchEnvironment["UI_TEST_ACTIVITY_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["UI_TEST_SOCIAL_FIXTURE"] = "1"
        if accelerated { app.launchEnvironment["UI_TEST_ACTIVITY_CADENCE"] = "accelerated" }
        app.launch()
        XCTAssertTrue(app.buttons["activities.tab.cafe"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["activities.tab.park"].exists)
        XCTAssertFalse(app.buttons["activities.tab.pond"].exists)
        return app
    }
    private func attach(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways
        add(image)
    }
    private func edgeBack(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
    }
    private func tap(_ id: String, app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 8), id)
        for _ in 0..<3 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        button.tap()
    }

    func testCafeSocialConversationFriendAndChatHandoff() {
        let app = launch()
        defer { app.terminate() }
        attach("cafe-scene", app: app)
        tap("activities.scene.cafe-seat", app: app)
        attach("cafe-introduction", app: app)
        tap("activities.action.start", app: app)
        tap("activities.choice.0", app: app)
        tap("activities.action.next", app: app)
        attach("cafe-social-choice", app: app)
        tap("activities.choice.0", app: app)
        tap("activities.action.next", app: app)
        attach("cafe-social-summary", app: app)
        tap("activities.encounter.addFriend", app: app)
        XCTAssertTrue(app.staticTexts["activities.encounter.contactStatus"].waitForExistence(timeout: 5))
        tap("activities.encounter.chat", app: app)
        XCTAssertTrue(app.buttons["返回咖啡馆"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "加载会话失败")).firstMatch.exists)
        attach("cafe-existing-chat", app: app)
        app.buttons["返回咖啡馆"].tap()
        tap("activities.action.finish", app: app)
        tap("activities.journal", app: app)
        XCTAssertTrue(app.navigationBars["相遇与足迹"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["与 Alex 的这次交流"].exists)
        attach("cafe-encounter-journal", app: app)
        app.buttons["完成"].tap()
        edgeBack(app)
        XCTAssertTrue(app.buttons["城市活动"].waitForExistence(timeout: 4))
    }

    func testGoodbyeDoesNotOfferFriendshipAndBothBackLevelsWork() {
        let app = launch()
        defer { app.terminate() }
        tap("activities.scene.cafe-book", app: app)
        edgeBack(app)
        XCTAssertTrue(app.buttons["activities.scene.cafe-neighbourhood"].waitForExistence(timeout: 4))
        tap("activities.scene.cafe-neighbourhood", app: app)
        tap("activities.action.start", app: app)
        tap("activities.choice.1", app: app)
        tap("activities.action.next", app: app)
        tap("activities.choice.1", app: app)
        tap("activities.action.next", app: app)
        XCTAssertFalse(app.buttons["activities.encounter.addFriend"].exists)
        XCTAssertFalse(app.buttons["activities.encounter.chat"].exists)
        attach("cafe-respectful-goodbye", app: app)
        tap("activities.action.finish", app: app)
        edgeBack(app)
        XCTAssertTrue(app.buttons["城市活动"].waitForExistence(timeout: 4))
    }

    func testThreeRealAmbientEventsStaticFallbackAndLifecycle() {
        let app = launch(accelerated: true)
        defer { app.terminate() }
        let motion = app.buttons["activities.motion"]
        let three = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (motion.value as? String ?? "").contains("循环3")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [three], timeout: 30), .completed)
        attach("cafe-after-three-events", app: app)
        motion.tap()
        XCTAssertEqual(motion.value as? String, "静态")
        attach("cafe-static", app: app)
        motion.tap()
        app.tabBars.buttons["我的"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.buttons["activities.scene.cafe-seat"].waitForExistence(timeout: 5))
    }
}
