import XCTest

@MainActor
final class OnboardingWelcomeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
    }

    override func tearDown() async throws {
        app.terminate()
        app = nil
    }

    func testWelcomeExplainsTheProductAndBeginsTheExistingOnboardingFlow() {
        app.launchEnvironment["UI_TEST_REQUIRE_AUTHENTICATION"] = "1"
        app.launchEnvironment["UI_TEST_FORCE_SIGNED_OUT"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["走进城市生活"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["welcome.begin"].exists)

        advance(toEyebrow: "会记住你的 AI 旅伴")

        advance(toEyebrow: "随时点词")

        let back = app.buttons["welcome.back"]
        XCTAssertTrue(back.exists)
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.staticTexts["会记住你的 AI 旅伴"].waitForExistence(timeout: 2))

        advance(toEyebrow: "随时点词")
        advance(toEyebrow: "你的第一位旅伴")

        let begin = app.buttons["welcome.begin"]
        XCTAssertTrue(begin.exists)
        XCTAssertTrue(begin.isHittable)
        begin.tap()

        XCTAssertTrue(begin.waitForNonExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["继续你的语言之旅"].waitForExistence(timeout: 5),
            "欢迎页完成后必须进入登录页"
        )
        XCTAssertTrue(app.buttons["使用邮箱登录或注册"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "未登录时不得显示主界面")
    }

    func testWelcomeSupportsDirectSwipePaging() {
        app.launch()

        XCTAssertTrue(app.staticTexts["走进城市生活"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["welcome.concept.activity"].firstMatch.exists)
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["会记住你的 AI 旅伴"].waitForExistence(timeout: 3))
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["走进城市生活"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["welcome.concept.activity"].firstMatch.exists)
    }

    func testAccessibilityTextKeepsWelcomeNavigationReachable() {
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["走进城市生活"].waitForExistence(timeout: 8))
        for eyebrow in ["会记住你的 AI 旅伴", "随时点词", "你的第一位旅伴"] {
            advance(toEyebrow: eyebrow)
        }
        XCTAssertTrue(app.buttons["welcome.begin"].isHittable)
        XCTAssertTrue(app.buttons["welcome.back"].isHittable)
    }

    func testStarterSelectionUsesBundledPortraitInsteadOfInitialPlaceholder() {
        app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "0"
        app.launchEnvironment["UI_TEST_ONBOARDING_SELECTION"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["选择你的第一位旅伴"].waitForExistence(timeout: 8))

        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        assertCenteredPortrait(regionID: "london", expectedLabel: "Oliver Bennett")
        captureScreen(named: "starter-oliver")
        scroll.swipeLeft()
        assertCenteredPortrait(regionID: "melbourne", expectedLabel: "Ruby Walker")
        captureScreen(named: "starter-ruby")
        scroll.swipeLeft()
        assertCenteredPortrait(regionID: "newyork", expectedLabel: "Marcus Rivera")
        captureScreen(named: "starter-marcus")
    }

    func testStarterSelectionButtonCompletesTheFlow() {
        app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "0"
        app.launchEnvironment["UI_TEST_ONBOARDING_SELECTION"] = "1"
        app.launch()

        let title = app.staticTexts["选择你的第一位旅伴"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        let confirm = app.buttons["onboarding.selection.confirm"]
        XCTAssertTrue(confirm.exists)
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()

        XCTAssertTrue(title.waitForNonExistence(timeout: 8), "选择成功后应离开选角页")
        XCTAssertTrue(app.buttons["tutorial.skip"].waitForExistence(timeout: 5))
        app.buttons["tutorial.skip"].tap()
        XCTAssertTrue(app.buttons["tutorial.skip"].waitForNonExistence(timeout: 8))
    }

    func testStarterSelectionFailureCanRetry() {
        app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "0"
        app.launchEnvironment["UI_TEST_ONBOARDING_SELECTION"] = "1"
        app.launchEnvironment["UI_TEST_ONBOARDING_SELECTION_FAILURE"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["选择你的第一位旅伴"].waitForExistence(timeout: 8))
        let confirm = app.buttons["onboarding.selection.confirm"]
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()

        XCTAssertTrue(app.buttons["tutorial.skip"].waitForExistence(timeout: 5))
        app.buttons["tutorial.skip"].tap()
        XCTAssertTrue(app.alerts["暂时无法出发"].waitForExistence(timeout: 3))
        app.alerts.buttons["稍后再试"].tap()
        XCTAssertTrue(app.buttons["tutorial.skip"].isEnabled)
    }

    func testHandsOnTutorialUsesLocalTranslationDictionaryAndEncounter() {
        let original = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = original }
        XCUIDevice.shared.appearance = .dark
        app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "0"
        app.launchEnvironment["UI_TEST_ONBOARDING_SELECTION"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.selection.confirm"].waitForExistence(timeout: 8))
        app.buttons["onboarding.selection.confirm"].tap()
        let bubble = app.descendants(matching: .any)["tutorial.bubble"].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tutorial.next"].isEnabled)
        bubble.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["翻译"].waitForExistence(timeout: 3))
        app.buttons["翻译"].tap()
        XCTAssertTrue(app.staticTexts["tutorial.translation"].waitForExistence(timeout: 3))
        captureScreen(named: "tutorial-translation")
        app.buttons["tutorial.next"].tap()
        let word = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "lovely")).firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 3))
        word.tap()
        XCTAssertTrue(app.buttons["播放读音"].waitForExistence(timeout: 3))
        app.staticTexts["上手试一试"].tap()
        app.buttons["tutorial.next"].tap()
        app.buttons["tutorial.outing"].tap()
        app.buttons["tutorial.choice.a"].tap()
        let add = app.buttons["tutorial.addFriend"]
        if !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(app.staticTexts["已体验添加好友"].exists)
        captureScreen(named: "tutorial-encounter")
        app.buttons["tutorial.next"].tap()
        captureScreen(named: "tutorial-explore")
        XCTAssertTrue(app.buttons["tutorial.next"].isEnabled)
    }

    func testOpeningChoicesAppearAsMessagesAndReachSelection() {
        app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "0"
        app.launchEnvironment["UI_TEST_ONBOARDING_STORY"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews["onboarding.story.messages"].waitForExistence(timeout: 10))
        var choices = 0
        for _ in 0..<55 {
            if app.buttons["onboarding.selection.confirm"].exists { break }
            let option = app.buttons["onboarding.story.choice.2"]
            if option.exists {
                XCTAssertTrue(app.buttons["onboarding.story.choice.0"].exists)
                XCTAssertTrue(app.buttons["onboarding.story.choice.1"].exists)
                captureScreen(named: "opening-choice-\(choices)")
                option.tap()
                choices += 1
            } else {
                advanceStory()
                XCTAssertFalse(app.buttons["onboarding.story.continue"].exists)
            }
        }
        XCTAssertEqual(choices, 1)
        XCTAssertTrue(app.buttons["onboarding.selection.confirm"].waitForExistence(timeout: 5))
    }

    func testIntroductionCanBeRevisitedWithoutRestartingOnboarding() {
        app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "0"
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "me"
        app.launch()
        let settings = app.buttons["设置，AI、语音与偏好"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let introduction = app.buttons["settings.introduction"]
        for _ in 0..<5 where !introduction.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(introduction.isHittable)
        introduction.tap()
        XCTAssertTrue(app.buttons["welcome.next"].waitForExistence(timeout: 5))
        for _ in 0..<3 { app.buttons["welcome.next"].tap() }
        app.buttons["welcome.begin"].tap()
        XCTAssertTrue(app.scrollViews["onboarding.story.messages"].waitForExistence(timeout: 5))
        app.buttons["introduction.close"].tap()
        XCTAssertTrue(introduction.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.selection.confirm"].exists)
    }

    func testTutorialCanBeReplayedWithoutSelectingAnotherCompanion() {
        app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "0"
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "me"
        app.launch()
        let settings = app.buttons["设置，AI、语音与偏好"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let entry = app.buttons["settings.tutorial"]
        for _ in 0..<5 where !entry.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.buttons["tutorial.skip"].waitForExistence(timeout: 5))
        app.buttons["tutorial.skip"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.selection.confirm"].exists)
    }

    func testWelcomeVisuals() {
        let original = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = original }
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = appearance
            app.launch()
            XCTAssertTrue(app.buttons["welcome.next"].waitForExistence(timeout: 8))
            for page in 0..<4 {
                let names = ["activity", "chat", "dictionary", "companion"]
                let image = app.descendants(matching: .any)["welcome.concept.\(names[page])"].firstMatch
                XCTAssertTrue(image.waitForExistence(timeout: 3))
                let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    abs(image.frame.midX - self.app.frame.midX) < 2
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 3), .completed)
                if page == 0 {
                    for label in ["信息", "联系人", "活动", "我的"] {
                        XCTAssertTrue(image.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch.exists)
                    }
                } else if page == 2 {
                    XCTAssertTrue(image.staticTexts["spontaneous"].waitForExistence(timeout: 3))
                    XCTAssertTrue(image.staticTexts["Are you a spontaneous person?"].exists)
                } else if page == 3 {
                    XCTAssertTrue(image.descendants(matching: .any)["onboarding.character.avatar.london"].firstMatch.exists)
                    for label in ["表达难度", "开口辅助", "动态调整"] {
                        XCTAssertFalse(image.staticTexts[label].exists)
                    }
                }
                captureScreen(named: "welcome-\(appearance)-\(page)")
                if page < 3 { app.buttons["welcome.next"].tap() }
            }
            app.terminate()
        }
    }

    private func advanceStory() {
        let messages = app.scrollViews["onboarding.story.messages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.45)).tap()
    }

    func testStoryScrollsToNewCardsAndWordLookupDoesNotAdvance() {
        app.launchEnvironment["UI_TEST_ONBOARDING_WELCOME"] = "0"
        app.launchEnvironment["UI_TEST_ONBOARDING_STORY"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews["onboarding.story.messages"].waitForExistence(timeout: 10))
        for region in ["london", "melbourne", "newyork"] {
            let card = app.otherElements["onboarding.intro.\(region)"]
            for _ in 0..<5 where !card.exists { advanceStory() }
            XCTAssertTrue(card.waitForExistence(timeout: 3))
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                card.frame.maxY <= self.app.frame.maxY - 8 && card.frame.minY > 0
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 3), .completed)
            captureScreen(named: "opening-card-\(region)")
        }
        // The short English invitation remains a real lookup target; a word tap must not progress.
        let word = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "photographer")).firstMatch
        XCTAssertTrue(word.exists)
        XCTAssertFalse(app.staticTexts["onboarding.story.line.6.paragraph.0"].exists)
        word.tap()
        XCTAssertTrue(app.staticTexts["photographer"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["onboarding.story.line.6.paragraph.0"].exists)
        XCTAssertFalse(app.buttons["onboarding.story.choice.0"].exists)
        captureScreen(named: "opening-word-lookup")
    }

    private func advance(toEyebrow eyebrow: String) {
        let next = app.buttons["welcome.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 2))
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.staticTexts[eyebrow].waitForExistence(timeout: 3))
    }

    private func assertCenteredPortrait(regionID: String, expectedLabel: String) {
        let avatar = app.descendants(matching: .any)["onboarding.character.avatar.\(regionID)"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 3))
        XCTAssertEqual(avatar.label, expectedLabel)
        let windowMidX = app.windows.firstMatch.frame.midX
        let centered = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return abs(element.frame.midX - windowMidX) <= 2
        }
        let expectation = XCTNSPredicateExpectation(predicate: centered, object: avatar)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 2),
            .completed,
            "\(expectedLabel) 的人物卡应吸附在屏幕正中"
        )
    }

    private func captureScreen(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in elements.contains { $0.exists } },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
