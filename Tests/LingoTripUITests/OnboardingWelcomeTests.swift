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

        XCTAssertTrue(app.staticTexts["让英语，发生在旅途中。"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["走进城市"].exists)
        XCTAssertTrue(app.staticTexts["遇见旅伴"].exists)
        XCTAssertTrue(app.staticTexts["随时点词"].exists)

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
