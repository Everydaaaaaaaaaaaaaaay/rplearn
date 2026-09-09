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
            waitForAny(
                [
                    app.staticTexts["先认识一下你"],
                    app.staticTexts["要不要再校准一下？"],
                    app.staticTexts["开始旅程 2 / 3"],
                ],
                timeout: 5
            ),
            "欢迎页应进入建档、可选校准或已有进度对应的剧情阶段"
        )
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
        assertPortrait(regionID: "london", expectedLabel: "Oliver Bennett")
        scroll.swipeLeft()
        assertPortrait(regionID: "melbourne", expectedLabel: "Ruby Walker")
        scroll.swipeLeft()
        assertPortrait(regionID: "newyork", expectedLabel: "Marcus Rivera")
    }

    private func advance(toEyebrow eyebrow: String) {
        let next = app.buttons["welcome.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 2))
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.staticTexts[eyebrow].waitForExistence(timeout: 3))
    }

    private func assertPortrait(regionID: String, expectedLabel: String) {
        let avatar = app.descendants(matching: .any)["onboarding.character.avatar.\(regionID)"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 3))
        XCTAssertEqual(avatar.label, expectedLabel)
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
