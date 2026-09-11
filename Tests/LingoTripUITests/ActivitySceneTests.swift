import XCTest

@MainActor
final class ActivitySceneTests: XCTestCase {
    private func launch(extra: [String: String] = [:], appearance: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        if let appearance { XCUIDevice.shared.appearance = appearance == "Dark" ? .dark : .light }
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_HOME_DESTINATION"] = "activities"
        app.launchEnvironment["UI_TEST_ACTIVITY_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["UI_TEST_SOCIAL_FIXTURE"] = "1"
        for (key, value) in extra { app.launchEnvironment[key] = value }
        app.launch()
        XCTAssertTrue(app.buttons["activities.tab.park"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["activities.tab.pond"].exists)
        XCTAssertTrue(app.buttons["activities.tab.raincafe"].exists)
        XCTAssertFalse(app.buttons["activities.tab.cafe"].exists)
        XCTAssertFalse(app.buttons["activities.tab.bookstall"].exists)
        XCTAssertFalse(app.buttons["activities.tab.flowerstall"].exists)
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
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
    }

    private func tap(_ id: String, app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: (id.hasPrefix("activities.choice") || id == "activities.action.next") ? 20 : 8), id)
        for _ in 0..<3 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        button.tap()
    }

    private func finishChapter(_ app: XCUIApplication, choice: Int) {
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 22))
        attach("chapter-opening", app: app)
        for stage in 0..<3 {
            for _ in 0..<3 { tap("activities.action.next", app: app) }
            if stage < 2 { tap("activities.choice.\(choice)", app: app) }
            else { tap("activities.action.next", app: app) }
        }
        attach("chapter-friendship-choice", app: app)
    }

    private func waitFor(_ text: String, status: XCUIElement, timeout: TimeInterval) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (status.value as? String ?? "").contains(text)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, text)
    }

    func testEncounterAppearance() {
        let originalAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = originalAppearance }
        for appearance in ["Dark", "Light"] {
            let app = launch(appearance: appearance)
            tap("activities.scene.park-seat", app: app)
            attach("encounter-confirmation-\(appearance)", app: app)
            tap("activities.action.start", app: app)
            XCTAssertTrue(app.otherElements["activities.journey"].waitForExistence(timeout: 3))
            attach("encounter-journey-\(appearance)", app: app)
            XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 20))
            attach("encounter-story-\(appearance)", app: app)
            XCTAssertTrue(app.switches["自动播放台词"].exists)
            app.terminate()
        }
    }

    func testJourneyKeepsTabsAvailableAndCompletesOffscreen() {
        let app = launch()
        defer { app.terminate() }
        tap("activities.scene.park-seat", app: app)
        tap("activities.action.start", app: app)
        XCTAssertTrue(app.otherElements["activities.journey"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["我的"].isHittable)
        attach("journey-glass-countdown", app: app)
        app.tabBars.buttons["我的"].tap()
        XCTAssertFalse(app.buttons["activities.choice.0"].exists)
        // Wall-clock deadline runs offscreen; no application navigation should occur.
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.tabBars.buttons["首页"].value as? String == "•"
        }, object: nil)
        _ = XCTWaiter.wait(for: [wait], timeout: 16)
        XCTAssertTrue(app.tabBars.buttons["我的"].isSelected)
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["activities.journey"].exists)
        attach("journey-encounter-result", app: app)
        tap("activities.action.next", app: app)
        app.tabBars.buttons["我的"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 4))
    }

    func testJourneySolitudeCanBeSaved() {
        let app = launch(extra: ["UI_TEST_SOLITUDE": "1"])
        defer { app.terminate() }
        tap("activities.scene.park-seat", app: app)
        tap("activities.action.start", app: app)
        XCTAssertTrue(app.buttons["activities.solitude.finish"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["activities.encounter.addFriend"].exists)
        attach("journey-solitude-result", app: app)
        tap("activities.solitude.finish", app: app)
        tap("activities.journal", app: app)
        XCTAssertTrue(app.staticTexts["留给自己的座位"].waitForExistence(timeout: 4))
    }

    func testJourneyFailureRetryDoesNotReplayCountdown() {
        let app = launch(extra: ["UI_TEST_JOURNEY_FAILURE_FIRST": "1"])
        defer { app.terminate() }
        tap("activities.scene.park-seat", app: app)
        tap("activities.action.start", app: app)
        XCTAssertTrue(app.buttons["activities.journey.retry"].waitForExistence(timeout: 20))
        attach("journey-failure", app: app)
        app.buttons["activities.journey.retry"].tap()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.otherElements["activities.journey"].exists)
    }

    func testJourneyWaitsNaturallyAfterFifteenSeconds() {
        let app = launch(extra: ["UI_TEST_JOURNEY_DELAY": "1"])
        defer { app.terminate() }
        tap("activities.scene.park-seat", app: app)
        tap("activities.action.start", app: app)
        XCTAssertTrue(app.staticTexts["相遇正在途中"].waitForExistence(timeout: 17))
        attach("journey-waiting", app: app)
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 6))
    }

    func testRealMotionScenesAtNativeSize() {
        let app = launch()
        defer { app.terminate() }
        for scene in ["park", "pond", "raincafe"] {
            tap("activities.tab.\(scene)", app: app)
            let motion = app.buttons["activities.motion"]
            if motion.value as? String != "静态" { motion.tap() }
            XCTAssertEqual(motion.value as? String, "静态")
            XCTAssertFalse(app.staticTexts["情景美术 · 非城市实拍 / 实时画面"].exists)
            attach("real-motion-v5-\(scene)", app: app)
        }
    }

    func testEntranceMarginsOpenTheirOwnActionAndReturn() {
        let app = launch()
        defer { app.terminate() }
        let scenes: [(String, [(String, String)])] = [
            ("park", [("park-route", "问问路线"), ("park-seat", "喝口咖啡"), ("park-notes", "交换见闻")]),
            ("pond", [("pond-reflection", "看看倒影"), ("pond-sketch", "聊聊速写"), ("pond-postcard", "写张短笺")]),
            ("raincafe", [("rain-weather", "聊聊雨天"), ("rain-pastry", "分享点心"), ("rain-napkin", "递张纸巾")])
        ]
        for (scene, entries) in scenes {
            tap("activities.tab.\(scene)", app: app)
            for (index, entry) in entries.enumerated() {
                let button = app.buttons["activities.scene.\(entry.0)"]
                XCTAssertTrue(button.waitForExistence(timeout: 5), entry.0)
                XCTAssertGreaterThanOrEqual(button.frame.width, 44)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                button.coordinate(withNormalizedOffset:
                    CGVector(dx: index.isMultiple(of: 2) ? 0.08 : 0.92, dy: 0.5)).tap()
                XCTAssertTrue(app.buttons["activities.action.start"].waitForExistence(timeout: 4))
                XCTAssertTrue(app.staticTexts[entry.1].firstMatch.exists)
                edgeBack(app)
                XCTAssertTrue(button.waitForExistence(timeout: 4))
            }
            attach("real-motion-v5-entrances-\(scene)", app: app)
        }
    }

    func testParkSocialConversationFriendAndChatHandoff() {
        let app = launch()
        defer { app.terminate() }
        attach("park-scene", app: app)
        tap("activities.scene.park-seat", app: app)
        tap("activities.action.start", app: app)
        finishChapter(app, choice: 0)
        tap("activities.encounter.addFriend", app: app)
        XCTAssertTrue(app.staticTexts["activities.encounter.contactStatus"].waitForExistence(timeout: 5))
        tap("activities.encounter.chat", app: app)
        XCTAssertTrue(app.buttons["返回城市活动"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "加载会话失败")).firstMatch.exists)
        app.buttons["返回城市活动"].tap()
        tap("activities.action.finish", app: app)
        tap("activities.journal", app: app)
        XCTAssertTrue(app.navigationBars["相遇与足迹"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["与 Alex 的这次交流"].exists)
        app.buttons["完成"].tap()
        edgeBack(app)
        XCTAssertTrue(app.buttons["城市活动"].waitForExistence(timeout: 4))
    }

    func testChapterSupportsWordLookupAndVoice() {
        let app = launch()
        defer { app.terminate() }
        tap("activities.scene.park-route", app: app)
        tap("activities.action.start", app: app)
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 22))
        let word = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "map\\s*")).firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 4))
        word.tap()
        XCTAssertTrue(app.buttons["播放读音"].waitForExistence(timeout: 5))
        attach("chapter-word-lookup", app: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.24)).tap()
        XCTAssertFalse(app.buttons["播放读音"].exists)
        tap("activities.action.next", app: app)
        XCTAssertTrue(app.buttons["播放台词"].waitForExistence(timeout: 4))
        app.buttons["播放台词"].tap()
        XCTAssertTrue(app.buttons["停止"].exists)
        app.buttons["停止"].tap()
    }

    func testChapterAlwaysOffersFriendshipAndAllowsLeaving() {
        let app = launch()
        defer { app.terminate() }
        tap("activities.scene.park-notes", app: app)
        edgeBack(app)
        XCTAssertTrue(app.buttons["activities.scene.park-route"].waitForExistence(timeout: 4))
        tap("activities.scene.park-route", app: app)
        tap("activities.action.start", app: app)
        finishChapter(app, choice: 1)
        XCTAssertTrue(app.buttons["activities.encounter.addFriend"].exists)
        XCTAssertTrue(app.buttons["activities.encounter.chat"].exists)
        tap("activities.action.finish", app: app)
        edgeBack(app)
        XCTAssertTrue(app.buttons["城市活动"].waitForExistence(timeout: 4))
    }

    func testPondAndRainCafeContinueAcrossTwoRealLoopsAndLifecycleChanges() {
        let app = launch()
        defer { app.terminate() }
        let status = app.staticTexts["activities.playbackStatus"]
        for (scene, action) in [("pond", "pond-reflection"), ("raincafe", "rain-weather")] {
            tap("activities.tab.\(scene)", app: app)
            waitFor("播放中", status: status, timeout: 10)
            tap("activities.scene.\(action)", app: app)
            waitFor("循环1", status: status, timeout: 25)
            attach("\(scene)-conversation-motion", app: app)
            edgeBack(app)
            waitFor("循环2", status: status, timeout: 25)
            waitFor("秒3", status: status, timeout: 8)
            attach("\(scene)-second-seam", app: app)
            tap("activities.motion", app: app)
            XCTAssertEqual(app.buttons["activities.motion"].value as? String, "静态")
            attach("\(scene)-static-fallback", app: app)
            tap("activities.motion", app: app)
            waitFor("播放中", status: status, timeout: 5)
            XCUIDevice.shared.press(.home)
            app.activate()
            waitFor("播放中", status: status, timeout: 5)
        }
    }

    func testParkEnvironmentContinuesAfterRunnerLeaves() {
        let app = launch()
        defer { app.terminate() }
        let status = app.staticTexts["activities.playbackStatus"]
        waitFor("播放中", status: status, timeout: 10)
        waitFor("秒10", status: status, timeout: 15)
        waitFor("秒20", status: status, timeout: 15)
        waitFor("播放中", status: status, timeout: 2)
        attach("park-continuous-environment-after-runner", app: app)
        waitFor("循环1", status: status, timeout: 70)
        waitFor("秒4", status: status, timeout: 8)
        attach("park-second-sparse-runner-pass", app: app)
    }
}
