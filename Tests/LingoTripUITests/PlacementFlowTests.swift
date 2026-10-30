import XCTest

@MainActor
final class PlacementFlowTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "UI_TEST_PLACEMENT_QUESTION": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9"]
        app.launch()
        try? saveEvidence(app, name: "launched")
        XCTAssertTrue(app.buttons["placement.confirm"].waitForExistence(timeout: 15))
        return app
    }

    func testConfirmationBackAndThreeMistakes() throws {
        let app = launch()
        defer { app.terminate() }
        let confirm = app.buttons["placement.confirm"]
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertFalse(app.buttons["placement.previous"].isEnabled)
        let questionImage = XCTAttachment(screenshot: app.screenshot())
        questionImage.name = "基础起步与确认回退跳过按钮"; questionImage.lifetime = .keepAlways; add(questionImage)
        try saveEvidence(app, name: "question")
        // The foundation items all use original option 0 as their reference; display order is shuffled.
        let wrong = app.buttons["placement.option.1"]
        wrong.tap()
        XCTAssertTrue(app.staticTexts["第 1 题 / 20"].exists, "点选不得自动提交")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["第 2 题 / 20"].waitForExistence(timeout: 3))
        app.buttons["placement.previous"].tap()
        XCTAssertTrue(app.staticTexts["第 1 题 / 20"].waitForExistence(timeout: 3))
        XCTAssertTrue(confirm.isEnabled, "上一题应保留草稿")
        confirm.tap()
        wrong.tap(); confirm.tap()
        XCTAssertTrue(app.staticTexts["第 3 题 / 20"].waitForExistence(timeout: 3))
        wrong.tap(); confirm.tap()
        XCTAssertTrue(app.staticTexts["累计答错 3 次，本次测评已结束。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["placement.restart"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "三次确认错误后结束"; image.lifetime = .keepAlways; add(image)
        try saveEvidence(app, name: "three-mistakes-result")
        let restart = app.buttons["placement.restart"]
        for _ in 0..<4 where !restart.isHittable { app.swipeUp() }
        restart.tap()
        XCTAssertTrue(app.staticTexts["第 1 题 / 20"].waitForExistence(timeout: 3))
        XCTAssertFalse(confirm.isEnabled)
        try saveEvidence(app, name: "confirmation-back-restart-completed")
    }

    func testSkipDoesNotForceAPlacementOrRequireAudio() throws {
        let app = launch()
        defer { app.terminate() }
        for _ in 0..<20 {
            let skip = app.buttons["placement.skip"]
            if !skip.exists { break }
            skip.tap()
        }
        XCTAssertTrue(app.staticTexts["还需要一些作答信息"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["placement.apply"].exists)
        XCTAssertTrue(app.buttons["placement.chooseLevel"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "全部跳过不强制定级"; image.lifetime = .keepAlways; add(image)
        try saveEvidence(app, name: "skip-completed")
        let chooseLevel = app.buttons["placement.chooseLevel"]
        for _ in 0..<4 where !chooseLevel.isHittable { app.swipeUp() }
        chooseLevel.tap()
        XCTAssertTrue(app.staticTexts["选择英语水平"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["建议"].exists, "没有有效作答时不得推荐水平")
        try saveEvidence(app, name: "skip-manual-level")
        app.buttons["返回水平校准"].tap()
        XCTAssertTrue(app.staticTexts["还需要一些作答信息"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["placement.apply"].exists)
    }

    private func saveEvidence(_ app: XCUIApplication, name: String) throws {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("placement-v2", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(to: root.appendingPathComponent(name + ".png"))
        try app.debugDescription.write(to: root.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        let record: [String: Any] = ["stage": name, "failures": testRun?.failureCount ?? -1,
                                   "checkedAt": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent(name + ".json"))
    }
}
