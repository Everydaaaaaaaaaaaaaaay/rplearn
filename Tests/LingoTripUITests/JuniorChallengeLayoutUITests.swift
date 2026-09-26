import XCTest

/// 公开题面快照来自正式九年级内容；只检查交互，不在客户端实现判题或发奖。
@MainActor
final class JuniorChallengeLayoutUITests: XCTestCase {
    func testAuthoredLongQuestionsRemainOperable() throws {
        try exerciseCases(largeText: false)
    }

    func testLargeTextLongQuestionsRemainOperable() throws {
        try exerciseCases(largeText: true)
    }

    private func exerciseCases(largeText: Bool) throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "learning-junior3-preview", withExtension: "json"))
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        for item in cases {
            let unit = try XCTUnwrap(item["unit"] as? [String: Any])
            let questionID = try XCTUnwrap(item["questionId"] as? String)
            let questions = try XCTUnwrap(unit["questions"] as? [[String: Any]])
            let question = try XCTUnwrap(questions.first { $0["id"] as? String == questionID })
            let kind = try XCTUnwrap(question["type"] as? String)
            let app = XCUIApplication()
            app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
                "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
                "UI_TEST_LEARNING_UNIT_JSON": String(decoding: try JSONSerialization.data(withJSONObject: unit), as: UTF8.self),
                "UI_TEST_LEARNING_QUESTION_ID": questionID]
            if largeText {
                app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
                app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
            }
            app.launch()
            XCTAssertTrue(app.buttons["退出挑战"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["初中三年级"].exists)
            XCTAssertTrue(app.staticTexts[try XCTUnwrap(question["prompt"] as? String)].exists)
            capture(app, name: "九年级-\(kind)-初始")
            let check = app.buttons["检查"]
            XCTAssertFalse(check.isEnabled)
            switch kind {
            case "choice":
                let options = try XCTUnwrap(question["options"] as? [[String: String]])
                for option in options {
                    let button = app.buttons[try XCTUnwrap(option["text"])]
                    reveal(button, in: app); button.tap()
                    XCTAssertTrue(button.isSelected)
                    XCTAssertTrue(check.isEnabled)
                }
            case "arrange":
                let tokens = try XCTUnwrap(question["tokens"] as? [[String: String]])
                // 按词块身份点击，验证多词块能够换行和移回；不提交或判分。
                for token in tokens {
                    let button = app.buttons[try XCTUnwrap(token["text"])]
                    reveal(button, in: app); button.tap()
                }
                XCTAssertTrue(check.isEnabled)
                let selected = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 1 个词，")).firstMatch
                reveal(selected, in: app); selected.tap()
                XCTAssertTrue(app.buttons[try XCTUnwrap(tokens[0]["text"])].isEnabled)
            case "matching":
                let left = try XCTUnwrap(question["left"] as? [[String: String]])
                let right = try XCTUnwrap(question["right"] as? [[String: String]])
                for index in left.indices {
                    let leftButton = matchingButton(try XCTUnwrap(left[index]["text"]), in: app)
                    reveal(leftButton, in: app); leftButton.tap()
                    let rightButton = matchingButton(try XCTUnwrap(right[index]["text"]), in: app)
                    reveal(rightButton, in: app); rightButton.tap()
                    XCTAssertEqual(rightButton.value as? String, "已配对 \(index + 1)")
                    XCTAssertEqual(check.isEnabled, index == left.count - 1)
                }
            case "completion":
                let field = app.textFields["填写答案"]
                XCTAssertTrue(field.waitForExistence(timeout: 3))
                reveal(field, in: app); field.tap(); field.typeText("so that")
                XCTAssertEqual(field.value as? String, "so that")
                XCTAssertTrue(check.isEnabled)
                XCTAssertTrue(check.isHittable)
                XCTAssertLessThanOrEqual(check.frame.maxY, app.keyboards.firstMatch.frame.minY)
            default: XCTFail("本批未预期的题型：\(kind)")
            }
            capture(app, name: "九年级-\(kind)-已操作")
            XCTAssertTrue(app.buttons["退出挑战"].isHittable)
            app.terminate()
        }
    }

    private func matchingButton(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            let top = app.buttons["退出挑战"].frame.maxY + 12
            let bottom = app.buttons["检查"].frame.minY - 16
            if element.isHittable, element.frame.midY >= top, element.frame.midY <= bottom { return }
            let down = element.exists && element.frame.midY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (bottom - top) * (down ? 0.2 : 0.8)))
            let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (bottom - top) * (down ? 0.8 : 0.2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, "应能滚动到完整题目控件：\(element.label)")
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
