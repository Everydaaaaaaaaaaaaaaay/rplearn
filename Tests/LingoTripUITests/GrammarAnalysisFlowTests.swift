import XCTest

@MainActor
final class GrammarAnalysisFlowTests: XCTestCase {
    private func openAnalysis(mode: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "UI_TEST_MARKETING_CAPTURE": "1",
            "UI_TEST_GRAMMAR_FIXTURE": mode, "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9"]
        app.launch()
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby Walker")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 15)); ruby.tap()
        let message = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Amazing")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 8)); message.press(forDuration: 1.2)
        let grammar = app.buttons["语法解析"]
        XCTAssertTrue(grammar.waitForExistence(timeout: 3)); grammar.tap()
        XCTAssertTrue(app.staticTexts["本地知识库未命中"].waitForExistence(timeout: 5))
        return app
    }

    func testDirectAITabSucceedsAfterLocalMiss() {
        let app = openAnalysis(mode: "direct")
        defer { app.terminate() }
        app.segmentedControls["GrammarAnalysisSourcePicker"].buttons["AI 解析"].tap()
        XCTAssertTrue(app.staticTexts["感叹句中的省略"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["重新解析"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "grammar-direct-tab-success"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testRetryAndLocalButtonShareTheSameSuccessfulAnalysis() {
        let app = openAnalysis(mode: "retry")
        defer { app.terminate() }
        let picker = app.segmentedControls["GrammarAnalysisSourcePicker"]
        picker.buttons["AI 解析"].tap()
        let retry = app.buttons["重新解析"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(app.staticTexts["感叹句中的省略"].waitForExistence(timeout: 5))
        picker.buttons["本地解析"].tap()
        app.buttons["DirectAIGrammarAnalysisButton"].tap()
        XCTAssertTrue(app.staticTexts["感叹句中的省略"].exists)
        XCTAssertFalse(retry.exists)
    }
}
