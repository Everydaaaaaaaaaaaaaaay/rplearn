import XCTest

@MainActor
final class LearningSystemUITests: XCTestCase {
    func testRealListeningWithoutSubtitlesThenReview() {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING":"1","UI_TEST_DISABLE_BACKGROUND_REFRESH":"1",
            "UI_TEST_WELCOME_CAPTURE":"1","UI_TEST_NATIVE_CAPTURE":"learningSystem","UI_TEST_TAB":"contacts",
            "LINGOTRIP_BACKEND_URL":"http://127.0.0.1:9", "UI_TEST_LEARNING_V1_OWNER": UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.switches["learningSystem.enabled"].waitForExistence(timeout:30))
        let start = app.buttons["learningListening.start.1"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isEnabled, "Authored material must load from the actual bundle")
        start.tap()
        let play = app.buttons["learningListening.play"]
        XCTAssertTrue(play.waitForExistence(timeout:10))
        for _ in 0..<6 {
            let option=app.buttons["learningListening.option.0"]
            XCTAssertFalse(option.isEnabled, "Cannot answer without hearing audio")
            XCTAssertFalse(app.buttons["再听原文"].exists)
            play.tap()
            let predicate=NSPredicate(format:"enabled == true")
            let done=XCTNSPredicateExpectation(predicate:predicate,object:option)
            XCTAssertEqual(XCTWaiter.wait(for:[done],timeout:45),.completed,"Real TTS must finish; a timer or playback failure must not unlock answers")
            guard option.isEnabled else { return }
            option.tap()
        }
        XCTAssertTrue(app.staticTexts["learningListening.result"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["再听原文"].firstMatch.exists)
        let image=XCTAttachment(screenshot:app.screenshot());image.name="learning-v1-listening-result";image.lifetime = .keepAlways;add(image)
    }
}
