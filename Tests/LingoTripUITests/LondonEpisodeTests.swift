import XCTest

@MainActor
final class LondonEpisodeTests: XCTestCase {
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
        app.launchEnvironment["UI_TEST_EPISODE_AUDIO"] = "0"
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

    private func advanceUntil(_ id: String, limit: Int = 160) {
        for _ in 0..<limit {
            if app.buttons[id].exists { return }
            let next = app.buttons["episode.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 3))
            next.tap()
        }
        XCTFail("Did not reach \(id)")
    }

    private func advanceToNode(_ id: String) {
        for _ in 0..<160 {
            let value = app.buttons["episode.sound"].value as? String ?? ""
            if value.contains(";node:\(id);") { return }
            guard app.buttons["episode.next"].exists else { break }
            app.buttons["episode.next"].tap()
        }
        XCTFail("Did not reach node \(id)")
    }

    func testReadingRouteAndResume() {
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
        XCTAssertGreaterThan(app.buttons["episode.history"].frame.minY, 50)
        screenshot("london-01-arrival")
        advanceToNode("hello")
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
        advanceToNode("read_breath")
        screenshot("london-04-reading")
        advanceUntil("episode.restart")
        screenshot("london-05-ending")
        XCTAssertTrue(app.staticTexts["书架之间 · 他有稿却没报名，你如何帮忙？"].exists)
        XCTAssertTrue(app.staticTexts["本章影响：Oliver 自愿上场并读完一页，你在台下陪伴，随后给出了具体反馈。"].exists)
        XCTAssertTrue(app.staticTexts["这一站，你留下的选择"].exists)
        let replay = app.buttons["episode.restart"]
        let finish = app.buttons["episode.finish"]
        XCTAssertGreaterThanOrEqual(finish.frame.height, 48)
        XCTAssertGreaterThan(finish.frame.width, 250)
        XCTAssertLessThan(finish.frame.maxY, replay.frame.minY)
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
        app.buttons["episode.finish"].tap()
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
        advanceToNode("listen_room")
        screenshot("london-08-listening")
        advanceToNode("listen_notice")
        screenshot("london-08b-seated-response")
        advanceUntil("episode.restart")
        XCTAssertTrue(app.staticTexts["本章影响：你们留在台下；他私下分享了第一句，并决定下次带一页来。"].exists)
        XCTAssertTrue(app.staticTexts["先问 Nora 活动形式，不提 Oliver 的名字。"].exists)
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
        XCTAssertTrue(app.buttons["story.mainline"].waitForExistence(timeout: 5))
        app.buttons["story.mainline"].tap()
        let london = app.buttons["story.chapter.departures_london_v1"]
        XCTAssertTrue(london.waitForExistence(timeout: 10))
        london.tap()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
    }

    func testDepartureCollectionArtworkAndChoices() {
        let chapters = [
            "mainline_melbourne", "mainline_newyork", "mainline_capetown", "mainline_singapore",
            "city_london", "city_melbourne", "city_newyork", "city_capetown", "city_singapore",
            "city_dublin", "city_edinburgh", "city_vancouver", "city_auckland", "city_nairobi",
            "city_toronto", "city_sydney", "city_neworleans", "city_manchester", "city_kingston"
        ]
        for chapter in chapters {
            app.launchEnvironment["UI_TEST_DEPARTURE_RESOURCE"] = "departures_\(chapter)_v1"
            app.launch()
            XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15), chapter)
            advanceUntil("episode.choice.a", limit: 40)
            XCTAssertTrue(app.buttons["episode.choice.a"].isHittable, chapter)
            XCTAssertTrue(app.buttons["episode.choice.b"].isHittable, chapter)
            screenshot("\(chapter)-choice-stage")
            app.buttons["episode.choice.a"].tap()
            XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 5), chapter)
            XCTAssertFalse(app.staticTexts["episode.saveError"].exists, chapter)
            screenshot("\(chapter)-branch-stage")
            app.terminate()
        }
    }

    func testCaptionArtworkFollowsBothFinalChoices() {
        app.launchEnvironment["UI_TEST_DEPARTURE_RESOURCE"] = "departures_mainline_capetown_v1"
        for choice in ["a", "b"] {
            app.launch()
            XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
            advanceUntil("episode.choice.a", limit: 30)
            app.buttons["episode.choice.a"].tap()
            advanceUntil("episode.choice.\(choice)", limit: 30)
            app.buttons["episode.choice.\(choice)"].tap()
            advanceToNode("open")
            screenshot("capetown-final-caption-\(choice)")
            XCTAssertTrue(app.buttons["episode.next"].isHittable)
            app.terminate()
            app.launchEnvironment["UI_TEST_EPISODE_FRESH"] = "0"
            app.launch()
            XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 15))
            XCTAssertTrue((app.buttons["episode.sound"].value as? String)?.contains(";node:open;") == true)
            screenshot("capetown-restored-caption-\(choice)")
            app.terminate()
            app.launchEnvironment["UI_TEST_EPISODE_FRESH"] = "1"
        }
    }

    // Explicit device sampling, not an ordinary unit-test or release gate.
    func testDeviceStoryMemorySample() throws {
        guard ProcessInfo.processInfo.environment["LINGOTRIP_STORY_DEVICE_METRICS"] == "1" else {
            throw XCTSkip("Run explicitly on an isolated device-test bundle.")
        }
        app.launchEnvironment["UI_TEST_DEPARTURE_RESOURCE"] = "departures_mainline_capetown_v1"
        app.launchEnvironment["UI_TEST_EPISODE_AUDIO"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 20))
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTMemoryMetric(application: app)], options: options) {
            advanceUntil("episode.choice.a", limit: 30)
            app.buttons["episode.choice.a"].tap()
            advanceUntil("episode.choice.b", limit: 30)
            app.buttons["episode.choice.b"].tap()
            advanceUntil("episode.restart", limit: 30)
        }
        screenshot("device-story-memory-ending")
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
        for _ in 0..<40 {
            guard app.buttons["episode.next"].exists else { break }
            app.buttons["episode.next"].doubleTap()
        }
        XCTAssertTrue(app.buttons["episode.choice.private"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["episode.next"].exists)
        app.buttons["episode.choice.private"].tap()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 3))
    }

    func testNarrationStartsAndMuteStopsAutomaticAdvance() {
        app.launchEnvironment["UI_TEST_EPISODE_AUDIO"] = "1"
        app.launch()
        let sound = app.buttons["episode.sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 20))
        let began = NSPredicate(format: "value CONTAINS %@", "starts:1;")
        expectation(for: began, evaluatedWith: sound)
        waitForExpectations(timeout: 45)
        XCTAssertEqual(sound.label, "关闭剧情声音")
        app.buttons["episode.auto"].tap()
        XCTAssertTrue(app.staticTexts["空着的\n那把椅子"].exists)
        app.buttons["episode.auto"].tap()
        // A line is audible even with auto advance off. Muting stops it, while
        // ordinary reading remains manual and lookup retains its own play action.
        sound.tap()
        XCTAssertEqual(sound.label, "开启剧情声音")
        XCTAssertTrue((sound.value as? String)?.contains("completed:none") == true)
        app.buttons["episode.next"].tap()
        XCTAssertTrue(app.buttons["episode.next"].exists)
        sound.tap()
        let resumed = NSPredicate(format: "value CONTAINS %@", "starts:2;")
        expectation(for: resumed, evaluatedWith: sound)
        waitForExpectations(timeout: 45)
        app.buttons["episode.close"].tap()
        XCTAssertFalse(app.buttons["episode.close"].waitForExistence(timeout: 2))
    }

    func testAuditionEntryRemovedAndShortPages() {
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["episode.voices"].exists)
        app.buttons["episode.next"].tap()
        XCTAssertTrue(app.staticTexts["街角的小书店还亮着灯。"].waitForExistence(timeout: 3))
        screenshot("london-short-dialogue")
        app.terminate()
        app.launchEnvironment["UI_TEST_EPISODE_FRESH"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["街角的小书店还亮着灯。"].waitForExistence(timeout: 15))
    }

    func testDismissingLookupDoesNotRepeatNarration() {
        app.launchEnvironment["UI_TEST_EPISODE_AUDIO"] = "1"
        app.launch()
        let sound = app.buttons["episode.sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "starts:1;"), evaluatedWith: sound)
        waitForExpectations(timeout: 30)
        expectation(for: NSPredicate(format: "value CONTAINS %@", "completed:arrival;"), evaluatedWith: sound)
        waitForExpectations(timeout: 15)
        let word = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "rain\\s*")).firstMatch
        for pronounce in [false, true] {
            word.tap()
            XCTAssertTrue(app.buttons["播放读音"].waitForExistence(timeout: 5))
            if pronounce {
                app.buttons["播放读音"].tap()
                expectation(for: NSPredicate(format: "value CONTAINS %@", "starts:2;"), evaluatedWith: sound)
                waitForExpectations(timeout: 45)
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.24)).tap()
            XCTAssertFalse(app.buttons["播放读音"].exists)
            let pause = expectation(description: "No automatic re-reading after closing lookup")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { pause.fulfill() }
            wait(for: [pause], timeout: 7)
            XCTAssertTrue((sound.value as? String)?.contains(pronounce ? "starts:2;" : "starts:1;") == true)
            XCTAssertTrue(word.exists)
        }
    }

    func testPlayerHasNoAssignedVoiceAndKeepsReadingTime() {
        app.launch()
        XCTAssertTrue(app.buttons["episode.next"].waitForExistence(timeout: 20))
        advanceToNode("listen")
        let sound = app.buttons["episode.sound"]
        sound.tap()
        let quiet = expectation(description: "The player's line remains unvoiced")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { quiet.fulfill() }
        wait(for: [quiet], timeout: 7)
        XCTAssertTrue((sound.value as? String)?.contains("starts:0;completed:listen") == true)
        app.buttons["episode.auto"].tap()
        let reading = expectation(description: "Silent line is not skipped after 0.6 seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { reading.fulfill() }
        wait(for: [reading], timeout: 3)
        XCTAssertTrue((sound.value as? String)?.contains("completed:listen") == true)
        app.buttons["episode.auto"].tap()
        app.buttons["episode.next"].tap()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "starts:1;"), evaluatedWith: sound)
        waitForExpectations(timeout: 30)
    }
}
