import XCTest

@MainActor
final class ChatViewPerformanceTests: XCTestCase {
    func testTypingAndDeletingDraftPerformance() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_MARKETING_CAPTURE": "1", "UI_TEST_NATIVE_CAPTURE": "chat"
        ]
        app.launch()
        defer { app.terminate() }
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby Walker")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 15))
        ruby.tap()
        let field = app.descendants(matching: .any)["chat.composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

        let text = "A quiet day by the river."
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app), XCTClockMetric()], options: options) {
            field.typeText(text)
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
        XCTAssertEqual(field.value as? String, "")
    }
}
