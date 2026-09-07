import XCTest

@MainActor
final class ActivitySceneTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_HOME_DESTINATION"] = "activities"
        app.launchEnvironment["UI_TEST_ACTIVITY_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["UI_TEST_SOCIAL_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["activities.tab.cafe"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["activities.tab.park"].exists)
        XCTAssertFalse(app.buttons["activities.tab.pond"].exists)
        XCTAssertTrue(app.buttons["activities.tab.bookstall"].exists)
        XCTAssertTrue(app.buttons["activities.tab.flowerstall"].exists)
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

    func testRevisedSceneVisualsAtNativeSize() {
        let app = launch()
        defer { app.terminate() }
        for scene in ["cafe", "bookstall", "flowerstall"] {
            tap("activities.tab.\(scene)", app: app)
            let motion = app.buttons["activities.motion"]
            if motion.value as? String != "静态" { motion.tap() }
            XCTAssertEqual(motion.value as? String, "静态")
            let disclosure = app.staticTexts["activities.disclosure"]
            XCTAssertTrue(disclosure.exists)
            XCTAssertGreaterThan(disclosure.frame.minY, app.frame.height * 0.65)
            XCTAssertLessThan(disclosure.frame.maxY, app.frame.height - 80)
            attach("ambient-v4-\(scene)", app: app)
        }
    }

    func testEntranceMarginsOpenTheirOwnActionAndReturn() {
        let app = launch()
        defer { app.terminate() }
        let scenes: [(String, [(String, String)])] = [
            ("cafe", [("cafe-seat", "共用一桌"), ("cafe-neighbourhood", "聊聊附近"), ("cafe-taste", "聊聊口味")]),
            ("bookstall", [("bookstall-cover", "同翻一页"), ("bookstall-recommend", "交换推荐"), ("bookstall-travel", "聊聊见闻")]),
            ("flowerstall", [("flowerstall-colour", "聊聊花色"), ("flowerstall-bouquet", "一束心意"), ("flowerstall-queue", "等候闲聊")])
        ]
        for (scene, entries) in scenes {
            tap("activities.tab.\(scene)", app: app)
            for (index, entry) in entries.enumerated() {
                let button = app.buttons["activities.scene.\(entry.0)"]
                XCTAssertGreaterThanOrEqual(button.frame.width, 44)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                button.coordinate(withNormalizedOffset: CGVector(dx: index.isMultiple(of: 2) ? 0.08 : 0.92, dy: 0.5)).tap()
                XCTAssertTrue(app.buttons["activities.action.start"].waitForExistence(timeout: 4))
                XCTAssertTrue(app.staticTexts[entry.1].firstMatch.exists)
                edgeBack(app)
                XCTAssertTrue(button.waitForExistence(timeout: 4))
            }
            attach("entrances-v3-\(scene)", app: app)
        }
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
        XCTAssertTrue(app.buttons["返回城市活动"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "加载会话失败")).firstMatch.exists)
        attach("cafe-existing-chat", app: app)
        app.buttons["返回城市活动"].tap()
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
        tap("activities.scene.cafe-taste", app: app)
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

    func testBookstallAndFlowerstallSocialActionsReturnToTheirOwnScene() {
        let app = launch()
        defer { app.terminate() }
        for (scene, actions) in [
            ("cafe", ["cafe-seat", "cafe-neighbourhood", "cafe-taste"]),
            ("bookstall", ["bookstall-cover", "bookstall-recommend", "bookstall-travel"]),
            ("flowerstall", ["flowerstall-colour", "flowerstall-bouquet", "flowerstall-queue"])
        ] {
            tap("activities.tab.\(scene)", app: app)
            attach("\(scene)-scene", app: app)
            for action in actions {
                tap("activities.scene.\(action)", app: app)
                attach("\(action)-introduction", app: app)
                tap("activities.action.start", app: app)
                tap("activities.choice.0", app: app)
                tap("activities.action.next", app: app)
                // Both consent and respectful goodbye stay available in every scene.
                let invitesContact = action == actions[0]
                tap("activities.choice.\(invitesContact ? 0 : 1)", app: app)
                tap("activities.action.next", app: app)
                if invitesContact {
                    tap("activities.encounter.addFriend", app: app)
                    tap("activities.encounter.chat", app: app)
                    XCTAssertTrue(app.buttons["返回城市活动"].waitForExistence(timeout: 5))
                    app.buttons["返回城市活动"].tap()
                } else {
                    XCTAssertFalse(app.buttons["activities.encounter.addFriend"].exists)
                }
                attach("\(action)-summary", app: app)
                tap("activities.action.finish", app: app)
                XCTAssertTrue(app.buttons["activities.scene.\(action)"].waitForExistence(timeout: 5))
            }
            tap("activities.journal", app: app)
            XCTAssertTrue(app.navigationBars["相遇与足迹"].waitForExistence(timeout: 4))
            app.buttons["完成"].tap()
            XCTAssertTrue(app.buttons["activities.scene.\(actions[0])"].waitForExistence(timeout: 5))
        }
        // Strip swiping and left-edge navigation are separate gestures.
        app.scrollViews["activities.sceneStrip"].swipeRight()
        XCTAssertTrue(app.buttons["activities.scene.bookstall-cover"].waitForExistence(timeout: 5))
        edgeBack(app)
        XCTAssertTrue(app.buttons["城市活动"].waitForExistence(timeout: 4))
    }

    func testNewScenesContinueAcrossTwoRealLoopsAndStaticToggle() {
        let app = launch()
        defer { app.terminate() }
        let status = app.staticTexts["activities.playbackStatus"]
        func waitFor(_ text: String, timeout: TimeInterval) {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (status.value as? String ?? "").contains(text)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, text)
        }
        for (scene, action) in [("bookstall", "bookstall-cover"), ("flowerstall", "flowerstall-colour")] {
            tap("activities.tab.\(scene)", app: app)
            waitFor("播放中", timeout: 10)
            tap("activities.scene.\(action)", app: app)
            waitFor("循环1", timeout: 70)
            attach("\(scene)-conversation-motion", app: app)
            edgeBack(app)
            waitFor("循环2", timeout: 70)
            waitFor("秒3", timeout: 6)
            attach("\(scene)-second-seam", app: app)
            tap("activities.motion", app: app)
            XCTAssertEqual(app.buttons["activities.motion"].value as? String, "静态")
            attach("\(scene)-static-fallback", app: app)
            tap("activities.motion", app: app)
            waitFor("播放中", timeout: 5)
            XCUIDevice.shared.press(.home)
            app.activate()
            waitFor("播放中", timeout: 5)
        }
        tap("activities.tab.cafe", app: app)
        waitFor("播放中", timeout: 10)
        XCTAssertTrue(app.buttons["activities.scene.cafe-seat"].exists)
    }

    func testContinuousAmbientMotionDuringConversationAndAcrossTwoRealLoops() {
        let app = launch()
        defer { app.terminate() }
        let motion = app.buttons["activities.motion"]
        let status = app.staticTexts["activities.playbackStatus"]
        func waitFor(_ text: String, timeout: TimeInterval) {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (status.value as? String ?? "").contains(text)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, text)
        }
        waitFor("播放中", timeout: 10)
        tap("activities.scene.cafe-seat", app: app)
        waitFor("秒10", timeout: 15)
        attach("cafe-action-background-keeps-moving", app: app)
        tap("activities.action.start", app: app)
        waitFor("秒20", timeout: 15)
        edgeBack(app)
        // Real 60-second Core Animation timeline, never shortened DEBUG timers.
        // This validates playback state, NOT continuous human visual inspection.
        waitFor("循环1", timeout: 70)
        attach("cafe-first-continuous-seam", app: app)
        waitFor("循环2", timeout: 70)
        waitFor("秒5", timeout: 10)
        attach("cafe-second-continuous-seam", app: app)
        motion.tap()
        XCTAssertEqual(motion.value as? String, "静态")
        attach("cafe-static", app: app)
        motion.tap()
        waitFor("播放中", timeout: 5)
        XCUIDevice.shared.press(.home)
        app.activate()
        waitFor("播放中", timeout: 5)
        app.tabBars.buttons["我的"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.buttons["activities.scene.cafe-seat"].waitForExistence(timeout: 5))
        waitFor("播放中", timeout: 5)
    }
}
