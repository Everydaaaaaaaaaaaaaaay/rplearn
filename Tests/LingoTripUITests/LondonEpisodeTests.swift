import XCTest

@MainActor
final class LondonEpisodeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "home"
        app.launchEnvironment["UI_TEST_LONDON_EPISODE"] = "1"
        app.launchEnvironment["UI_TEST_EPISODE_FRESH"] = "1"
    }
    override func tearDown() async throws { app.terminate() }

    private func screenshot(_ name: String) {
        // Capture settled art, not the intentionally translucent middle of a crossfade.
        let settled = expectation(description: "Stage crossfade settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func advanceUntil(_ id: String, limit: Int = 80) {
        for _ in 0..<limit {
            if app.buttons[id].exists { return }
            let next = app.buttons["episode.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 3))
            next.tap()
        }
        XCTFail("Did not reach \(id)")
    }

    func testReadingRouteAndResume() {
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
        XCTAssertGreaterThan(app.buttons["episode.history"].frame.minY, 50)
        screenshot("london-01-arrival")
        app.buttons["episode.next"].tap()
        app.buttons["episode.next"].tap()
        screenshot("london-02-oliver")

        let translation = app.buttons["episode.translation"]
        translation.tap()
        XCTAssertEqual(translation.label, "显示中文翻译")
        translation.tap()
        advanceUntil("episode.choice.private")
        screenshot("london-03-choice")
        app.buttons["episode.choice.private"].tap()

        app.terminate()
        app.launchEnvironment["UI_TEST_EPISODE_FRESH"] = "0"
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["episode.title"].exists)

        advanceUntil("episode.choice.read")
        app.buttons["episode.choice.read"].tap()
        for _ in 0..<3 { app.buttons["episode.next"].tap() }
        screenshot("london-04-reading")
        advanceUntil("episode.restart")
        screenshot("london-05-ending")
        XCTAssertTrue(app.staticTexts["陪伴他完成了第一次试读"].exists)
        XCTAssertTrue(app.staticTexts["这一晚，你留下的选择"].exists)
        let replay = app.buttons["episode.restart"]
        XCTAssertGreaterThanOrEqual(replay.frame.height, 48)
        XCTAssertGreaterThan(replay.frame.width, 250)
        replay.tap()
        XCTAssertTrue(app.buttons["从头开始"].waitForExistence(timeout: 3))
        if app.buttons["取消"].exists {
            app.buttons["取消"].tap()
        } else {
            // iOS 26's popover confirmation uses an outside tap to cancel.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.25)).tap()
        }
        XCTAssertFalse(app.buttons["从头开始"].exists)
        app.buttons["episode.history"].tap()
        XCTAssertTrue(app.buttons["继续阅读"].waitForExistence(timeout: 3))
        app.buttons["继续阅读"].tap()
        app.buttons["episode.close"].tap()
        XCTAssertFalse(app.buttons["episode.close"].waitForExistence(timeout: 1))
    }

    func testLeadingEdgeReturnsAndHistoryPauses() {
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
        app.buttons["episode.auto"].tap()
        app.buttons["episode.history"].tap()
        XCTAssertTrue(app.buttons["继续阅读"].waitForExistence(timeout: 3))
        let heldHistory = expectation(description: "History pauses past the automatic line duration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.2) { heldHistory.fulfill() }
        wait(for: [heldHistory], timeout: 10)
        XCTAssertFalse(app.staticTexts["Oliver's message was simple: ‘A reading tonight. No homework, I promise.’"].exists)
        app.buttons["继续阅读"].tap()
        let word = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "rain\\s*")).firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 3))
        word.tap()
        XCTAssertTrue(app.buttons["播放读音"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["“翻译”在模拟设备上不受支持。若要测试此功能，请在真实设备上运行代码。"].exists)
        screenshot("london-06-word-lookup")
        let heldLookup = expectation(description: "Lookup pauses past the automatic line duration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.2) { heldLookup.fulfill() }
        wait(for: [heldLookup], timeout: 10)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.24)).tap()
        XCTAssertFalse(app.buttons["播放读音"].exists)
        XCTAssertTrue(word.exists)
        app.buttons["episode.auto"].tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.50))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.50))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertFalse(app.buttons["episode.close"].waitForExistence(timeout: 2))
    }

    func testListeningRouteAndHistoryRestart() {
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
        advanceUntil("episode.choice.format")
        app.buttons["episode.choice.format"].tap()
        screenshot("london-07-nora")
        advanceUntil("episode.choice.listen")
        app.buttons["episode.choice.listen"].tap()
        for _ in 0..<3 { app.buttons["episode.next"].tap() }
        screenshot("london-08-listening")
        advanceUntil("episode.restart")
        XCTAssertTrue(app.staticTexts["尊重他今晚先听的决定"].exists)
        XCTAssertTrue(app.staticTexts["先了解规则，不替他报名"].exists)
        app.buttons["episode.history"].tap()
        XCTAssertTrue(app.buttons["重玩"].waitForExistence(timeout: 3))
        app.buttons["重玩"].tap()
        XCTAssertTrue(app.buttons["从头开始"].waitForExistence(timeout: 3))
        app.buttons["从头开始"].tap()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["空着的\n那把椅子"].exists)
    }

    func testEntryThroughStoryHub() {
        app.launchEnvironment["UI_TEST_LONDON_EPISODE"] = "0"
        app.launch()
        let story = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "剧情，")).firstMatch
        XCTAssertTrue(story.waitForExistence(timeout: 15))
        story.tap()
        XCTAssertTrue(app.buttons["story.london.preview"].waitForExistence(timeout: 5))
        app.buttons["story.london.preview"].tap()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
    }

    func testLargeTextKeepsControlsReachable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
        XCTAssertGreaterThan(app.buttons["episode.history"].frame.minY, 50)
        XCTAssertLessThan(app.buttons["episode.next"].frame.maxY, app.frame.height - 15)
        screenshot("london-09-large-text")
        app.buttons["episode.next"].tap()
        XCTAssertTrue(app.buttons["episode.history"].isHittable)
    }

    func testRapidContinueKeepsChoiceBoundary() {
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
        // No debounce/wait is imposed by the new content crossfade.
        for _ in 0..<8 { app.buttons["episode.next"].doubleTap() }
        XCTAssertTrue(app.buttons["episode.choice.private"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["episode.next"].exists)
        app.buttons["episode.choice.private"].tap()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 3))
    }
}
