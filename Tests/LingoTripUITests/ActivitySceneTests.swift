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

    func testEncounterTranslationWholeChoicesAndScrolling() {
        let app = launch()
        defer { app.terminate() }
        tap("activities.tab.raincafe", app: app)
        tap("activities.scene.rain-napkin", app: app)
        tap("activities.action.start", app: app)
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 22))
        let identity = app.otherElements["activities.encounter.identity"]
        let identityFrame = identity.frame
        let translation = app.buttons["activities.story.translation"]
        XCTAssertEqual(translation.value as? String, "关闭")
        XCTAssertFalse(app.staticTexts["风里的地图"].exists)
        attach("encounter-rain-english", app: app)
        translation.tap()
        XCTAssertEqual(translation.value as? String, "开启")
        // The control must not also advance the global tap surface.
        XCTAssertFalse(app.otherElements["activities.beat.0.1"].exists)
        // Blank margin advances without competing with word buttons.
        let paragraph = app.otherElements["activities.beat.0.0"]
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 28, dy: paragraph.frame.midY)).tap()
        XCTAssertTrue(app.otherElements["activities.beat.0.1"].waitForExistence(timeout: 3))
        for _ in 0..<2 { tap("activities.action.next", app: app) }
        let choice = app.buttons["activities.choice.1"]
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        XCTAssertTrue(choice.isHittable, "新选项应自动滚动至可见位置")
        XCTAssertFalse(app.buttons["选择这项行动"].exists)
        XCTAssertEqual(identity.frame.minY, identityFrame.minY, accuracy: 1)
        XCTAssertEqual(identity.frame.height, identityFrame.height, accuracy: 1)
        let speech = app.buttons["activities.story.play"]
        speech.tap()
        XCTAssertEqual(speech.value as? String, "关闭")
        XCTAssertTrue(speech.isHittable)
        attach("encounter-rain-translated-choices", app: app)
        choice.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(app.otherElements["activities.beat.1.0"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.otherElements["activities.beat.1.1"].exists, "选项不能同时触发继续")
        XCTAssertTrue(app.otherElements["activities.beat.0.0"].exists, "已读剧情应继续保留")
        attach("encounter-rain-next-chapter", app: app)
    }

    func testPreparationIsCentered() {
        let app = launch()
        defer { app.terminate() }
        tap("activities.scene.park-seat", app: app)
        let start = app.buttons["activities.action.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isHittable)
        XCTAssertGreaterThan(start.frame.midY, app.frame.height * 0.4)
        XCTAssertLessThan(start.frame.midY, app.frame.height * 0.8)
        XCTAssertLessThan(start.frame.width, app.frame.width * 0.6)
        XCTAssertEqual(start.frame.midX, app.frame.midX, accuracy: 2)
        attach("centered-preparation", app: app)
    }

    func testEncounterAppearance() {
        let originalAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = originalAppearance }
        for appearance in ["Dark", "Light"] {
            let app = launch(appearance: appearance)
            tap("activities.scene.park-seat", app: app)
            XCTAssertTrue(app.buttons["activities.action.start"].waitForExistence(timeout: 5))
            attach("encounter-confirmation-\(appearance)", app: app)
            tap("activities.action.start", app: app)
            XCTAssertTrue(app.otherElements["activities.journey"].waitForExistence(timeout: 3))
            attach("encounter-journey-\(appearance)", app: app)
            XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 20))
            attach("encounter-story-\(appearance)", app: app)
            XCTAssertFalse(app.switches["自动播放台词"].exists)
            XCTAssertTrue(app.buttons["activities.story.play"].exists)
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
            app.tabBars.buttons["活动"].value as? String == "•"
        }, object: nil)
        _ = XCTWaiter.wait(for: [wait], timeout: 16)
        XCTAssertTrue(app.tabBars.buttons["我的"].isSelected)
        app.tabBars.buttons["活动"].tap()
        XCTAssertTrue(app.buttons["activities.action.next"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["activities.journey"].exists)
        attach("journey-encounter-result", app: app)
        tap("activities.action.next", app: app)
        app.tabBars.buttons["我的"].tap()
        app.tabBars.buttons["活动"].tap()
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

    func testParkEncounterFriendshipAndJournal() {
        let app = launch()
        defer { app.terminate() }
        attach("park-scene", app: app)
        tap("activities.scene.park-seat", app: app)
        tap("activities.action.start", app: app)
        finishChapter(app, choice: 0)
        XCTAssertFalse(app.buttons["activities.encounter.chat"].exists)
        app.buttons["回顾你的选择"].tap()
        attach("bilingual-choice-review", app: app)
        app.buttons["回顾你的选择"].tap()
        tap("activities.encounter.addFriend", app: app)
        XCTAssertTrue(app.staticTexts["activities.encounter.contactStatus"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activities.encounter.chat"].exists)
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
        let occupation = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "bicycle\\s*")).firstMatch
        XCTAssertTrue(occupation.waitForExistence(timeout: 4))
        occupation.tap()
        XCTAssertTrue(app.buttons["播放读音"].waitForExistence(timeout: 5))
        attach("occupation-word-lookup", app: app)
        app.buttons["关闭释义"].tap()
        let word = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "map\\s*")).firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 4))
        word.tap()
        XCTAssertFalse(app.otherElements["activities.beat.0.1"].exists)
        XCTAssertTrue(app.buttons["播放读音"].waitForExistence(timeout: 5))
        attach("chapter-word-lookup", app: app)
        app.buttons["关闭释义"].tap()
        XCTAssertTrue(app.buttons["播放读音"].waitForNonExistence(timeout: 3))
        tap("activities.action.next", app: app)
        tap("activities.story.play", app: app)
        XCTAssertTrue(app.otherElements["activities.beat.0.0"].exists)
        XCTAssertTrue(app.otherElements["activities.beat.0.1"].exists)

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
        XCTAssertFalse(app.buttons["activities.encounter.chat"].exists)
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
