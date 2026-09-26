import XCTest

@MainActor
final class ChallengeLayoutUITests: XCTestCase {
    func testQuestionControlsKeepExitAndPromptVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for kind in ["choice", "arrange", "matching", "completion"] {
            app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
            app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
            app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
            app.launchEnvironment["UI_TEST_TAB"] = "unit-challenge"
            app.launchEnvironment["UI_TEST_LEARNING_QUESTION"] = kind
            app.launch()
            let exit = app.buttons["退出挑战"]
            XCTAssertTrue(exit.waitForExistence(timeout: 15), kind)
            XCTAssertGreaterThanOrEqual(exit.frame.minY, 0, kind)
            XCTAssertLessThan(exit.frame.maxY, 180, kind)
            XCTAssertTrue(exit.isHittable, kind)
            XCTAssertTrue(app.staticTexts["这是一道工程检查题，用于观察题干换行和操作区域，不计入学习记录。"].exists, kind)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "真实窗口题型布局-\(kind)"; attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }
    func testListeningPlaybackSlowReplayAndBackgroundInterruption() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "unit-challenge"
        app.launchEnvironment["UI_TEST_LEARNING_QUESTION"] = "listeningChoice"
        app.launch()
        let play = app.buttons["learning.audio.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        app.buttons["First option"].tap()
        XCTAssertFalse(app.buttons["检查"].isEnabled)
        play.tap()
        XCTAssertTrue(app.buttons["停止播放"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["再听一遍"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["检查"].isEnabled)
        app.buttons["learning.audio.slow"].tap()
        XCTAssertTrue(app.buttons["停止播放"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["播放已中断，轻点继续听。不会自动外放。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["停止播放"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "听力播放与中断"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["退出挑战"].tap()
        XCTAssertTrue(app.buttons["保存进度，稍后继续"].waitForExistence(timeout: 3))
    }
    func testListeningFailureKeepsRetryAndSkipAvailable() {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "unit-challenge"
        app.launchEnvironment["UI_TEST_LEARNING_QUESTION"] = "dictation"
        app.launchEnvironment["UI_TEST_LEARNING_AUDIO_FAILURE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["重新载入"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["暂时跳过，留待补答"].isEnabled)
        XCTAssertFalse(app.buttons["检查"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "听写音频失败恢复"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
