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

        XCTAssertTrue(app.staticTexts["真实城市剧情"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["旧书店的晚间朗读"].exists)
        XCTAssertFalse(app.buttons["welcome.begin"].exists)

        advance(toEyebrow: "会记住你的 AI 旅伴")
        XCTAssertTrue(app.staticTexts["Ruby Walker"].exists)
        XCTAssertTrue(app.staticTexts["她记得：你更喜欢安静的地方"].waitForExistence(timeout: 2))

        advance(toEyebrow: "随时点词")
        XCTAssertTrue(app.staticTexts["adj. 自发的；自然流露的"].waitForExistence(timeout: 2))

        let back = app.buttons["welcome.back"]
        XCTAssertTrue(back.exists)
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.staticTexts["会记住你的 AI 旅伴"].waitForExistence(timeout: 2))

        advance(toEyebrow: "随时点词")
        advance(toEyebrow: "为你实时适配")
        XCTAssertTrue(app.staticTexts["选择第一位旅伴"].exists)
        XCTAssertTrue(app.staticTexts["Oliver"].exists)
        XCTAssertTrue(app.staticTexts["Ruby"].exists)
        XCTAssertTrue(app.staticTexts["Marcus"].exists)

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

        XCTAssertTrue(app.staticTexts["真实城市剧情"].waitForExistence(timeout: 8))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["会记住你的 AI 旅伴"].waitForExistence(timeout: 3))
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["真实城市剧情"].waitForExistence(timeout: 3))
    }

    func testAccessibilityTextKeepsWelcomeNavigationReachable() {
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["真实城市剧情"].waitForExistence(timeout: 8))
        for eyebrow in ["会记住你的 AI 旅伴", "随时点词", "为你实时适配"] {
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
        scroll.swipeLeft()
        assertCenteredPortrait(regionID: "melbourne", expectedLabel: "Ruby Walker")
        scroll.swipeLeft()
        assertCenteredPortrait(regionID: "newyork", expectedLabel: "Marcus Rivera")
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

        XCTAssertTrue(app.alerts["暂时无法出发"].waitForExistence(timeout: 3))
        app.alerts.buttons["再试一次"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        XCTAssertTrue(confirm.isEnabled)
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
