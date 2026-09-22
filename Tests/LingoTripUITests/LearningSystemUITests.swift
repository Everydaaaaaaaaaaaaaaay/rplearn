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
    func testInterruptedPlaybackAndRelaunchResumeSameQuestion() {
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING":"1", "UI_TEST_DISABLE_BACKGROUND_REFRESH":"1",
            "UI_TEST_WELCOME_CAPTURE":"1", "UI_TEST_NATIVE_CAPTURE":"learningSystem", "UI_TEST_TAB":"contacts",
            "UI_TEST_CAPTURE_APPEARANCE":"dark", "LINGOTRIP_BACKEND_URL":"http://127.0.0.1:9",
            "UI_TEST_LEARNING_V1_OWNER": UUID().uuidString]
        func openListening() {
            XCTAssertTrue(app.navigationBars["共同篇章"].waitForExistence(timeout:30))
            let start = app.buttons["learningListening.start.1"]
            for _ in 0..<8 where !start.isHittable { app.swipeUp() }
            XCTAssertTrue(start.isHittable); start.tap()
            XCTAssertTrue(app.buttons["learningListening.play"].waitForExistence(timeout:10))
        }
        app.launch(); openListening()
        app.buttons["learningListening.play"].tap()
        app.buttons["稍后继续"].tap()
        openListening()
        XCTAssertFalse(app.buttons["learningListening.option.0"].isEnabled, "Interrupted audio is not a completed listen")
        app.buttons["learningListening.play"].tap()
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"), object:app.buttons["learningListening.option.0"])
        XCTAssertEqual(XCTWaiter.wait(for:[ready], timeout:45),.completed)
        app.buttons["learningListening.option.0"].tap()
        XCTAssertTrue(app.staticTexts["第2/6题"].exists)
        let choices = (0..<3).map { app.buttons["learningListening.option.\($0)"].label }
        app.buttons["稍后继续"].tap()
        app.terminate(); app.launch(); openListening()
        XCTAssertTrue(app.staticTexts["第2/6题"].exists, "Restart must not reset or advance the question")
        XCTAssertEqual((0..<3).map { app.buttons["learningListening.option.\($0)"].label }, choices, "Persist shuffled options")
        XCTAssertFalse(app.buttons["learningListening.option.0"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "learning-v1-dark-resumed"; attachment.lifetime = .keepAlways; add(attachment)
    }

}
