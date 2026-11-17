import AVFoundation
import XCTest

@MainActor
final class VoiceMessageUITests: XCTestCase {
    func testOriginalAudioReplayAndTranscript() throws {
        continueAfterFailure = false
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 80_000))
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * 220 / 16_000) * 0.05)
        }
        try AVAudioFile(forWriting: source, settings: format.settings).write(from: buffer)
        defer { try? FileManager.default.removeItem(at: source) }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
            "UI_TEST_NATIVE_CAPTURE": "chat", "UI_TEST_VOICE_CAPTURE_FILE": source.path,
        ]
        app.launch()
        defer { app.terminate() }
        let voice = app.buttons["播放语音消息"].firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["消息已听"].firstMatch.waitForExistence(timeout: 3))
        let transcript = "Could we meet at the café by the river tomorrow?"
        XCTAssertFalse(app.staticTexts[transcript].exists)
        voice.tap()
        let playing = app.buttons["停止语音消息"].firstMatch
        XCTAssertTrue(playing.waitForExistence(timeout: 3))
        playing.tap()
        XCTAssertTrue(voice.waitForExistence(timeout: 3))
        voice.tap()
        XCTAssertTrue(playing.waitForExistence(timeout: 3))
        XCTAssertTrue(voice.waitForExistence(timeout: 12))
        voice.press(forDuration: 0.8)
        let viewText = app.buttons["查看文字"]
        XCTAssertTrue(viewText.waitForExistence(timeout: 3))
        viewText.tap()
        XCTAssertTrue(app.staticTexts[transcript].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Voice message with listened receipt and optional transcript"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        voice.press(forDuration: 0.8)
        app.buttons["隐藏文字"].tap()
        XCTAssertFalse(app.staticTexts[transcript].exists)
    }
}
