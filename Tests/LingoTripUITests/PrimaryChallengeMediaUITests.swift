import XCTest

/// 模拟器读取本工作树的正式素材：覆盖三角色实图、真录音播放结束与选图解锁，不提交成绩。
@MainActor
final class PrimaryChallengeMediaUITests: XCTestCase {
    /// 正式成人素材：未听完不能提交，听完后支持重播、慢速和听写输入。
    func testAdultRecordedListeningAndDictation() throws {
        continueAfterFailure = false
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appending(path: "Backend/config/learning")
        let cases = [("companion.undergraduate.small-mountain", "cet4.astra.a02"),
                     ("companion.undergraduate.small-mountain", "cet4.astra.b08")]
        for (unitID, questionID) in cases {
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "units/\(unitID).json"))) as? [String: Any])
            let questions = try XCTUnwrap(raw["questions"] as? [[String: Any]])
            let question = try XCTUnwrap(questions.first { $0["id"] as? String == questionID })
            let audio = try XCTUnwrap(question["audio"] as? [String: String])
            var visible = question.filter { ["id", "type", "goalId", "instruction", "prompt", "hint", "options"].contains($0.key) }
            visible["audio"] = ["assetId": try XCTUnwrap(audio["assetId"])]
            var unit = raw.filter { ["id", "version", "schemaVersion", "roleKey", "level", "title", "summary", "scene", "estimatedMinutes", "goalIds"].contains($0.key) }
            unit["questions"] = [visible]; unit["beats"] = []
            let app = XCUIApplication()
            app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
                "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
                "UI_TEST_LEARNING_LOCAL_MEDIA": "1", "UI_TEST_LEARNING_MEDIA_DIRECTORY": directory.path,
                "UI_TEST_LEARNING_UNIT_JSON": String(decoding: try JSONSerialization.data(withJSONObject: unit), as: UTF8.self),
                "UI_TEST_LEARNING_QUESTION_ID": questionID]
            app.launch()
            let check = app.buttons["检查"]
            XCTAssertTrue(check.waitForExistence(timeout: 15))
            let transcript = try XCTUnwrap(audio["text"])
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label == %@", transcript)).firstMatch.exists, "答前不显示原文")
            let play = app.buttons["learning.audio.play"]
            reveal(play, in: app)
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "播放听力"), object: play)], timeout: 10) == .completed)
            if question["type"] as? String == "dictation" {
                let input = app.textViews["填写答案"].exists ? app.textViews["填写答案"] : app.textFields["填写答案"]
                reveal(input, in: app); input.tap(); input.typeText("Please save a copy, not just a link.")
                let dismissKeyboard = app.buttons["收起键盘"]
                XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
                XCTAssertEqual(dismissKeyboard.frame.midY, check.frame.midY, accuracy: 2, "输入时共用一行操作，不增加独立键盘工具栏")
                XCTAssertFalse(app.buttons["暂时跳过，留待补答"].exists)
                dismissKeyboard.tap()
            } else {
                let option = app.buttons["learning.option.a"]
                reveal(option, in: app); option.tap()
            }
            XCTAssertFalse(check.isEnabled, "选择或输入不代替完整听音")
            reveal(play, in: app); play.tap()
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "再听一遍"), object: play)], timeout: 30) == .completed)
            XCTAssertTrue(check.isEnabled)
            XCTAssertLessThanOrEqual(app.otherElements["learning.audio.controls"].frame.height, 64)
            app.buttons["learning.audio.slow"].tap()
            XCTAssertTrue(app.buttons["停止播放"].waitForExistence(timeout: 5))
            play.tap()
            XCTAssertTrue(check.isEnabled, "已完整听过后，停止重播不撤销作答资格")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = questionID + "-正式音频"; attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }
    func testPrimaryPicturesAndRecordedAudio() throws { try exercise(large: false) }
    func testPrimaryPicturesLargeTextDark() throws { try exercise(large: true) }

    func testSecondGradeRecordedAudio() throws { try exercise(large: false, secondGrade: true) }
    func testSecondGradeLargeTextDark() throws { try exercise(large: true, secondGrade: true) }

    private func exercise(large: Bool, secondGrade: Bool = false) throws {
        continueAfterFailure = false
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appending(path: "Backend/config/learning")
        let ids = secondGrade ? ["oliver.primary2.playtime-can", "oliver.primary2.week-day-cards", "ruby.primary2.weather-window", "ruby.primary2.cafe-actions", "marcus.primary2.photo-time", "marcus.primary2.street-directions"] : ["oliver.primary1.bookmark-colours", "oliver.primary1.animal-book-covers", "ruby.primary1.shell-count", "ruby.primary1.painted-animal-flags", "marcus.primary1.photo-count", "marcus.primary1.studio-directions"]
        for id in ids {
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "units/\(id).json"))) as? [String: Any])
            let questions = try XCTUnwrap(raw["questions"] as? [[String: Any]])
            let question = try XCTUnwrap(questions.first)
            let publicQuestion = question.filter { ["id", "type", "goalId", "instruction", "prompt", "hint", "options"].contains($0.key) }
            var visible = publicQuestion
            let audio = try XCTUnwrap(question["audio"] as? [String: String])
            visible["audio"] = ["assetId": try XCTUnwrap(audio["assetId"])]
            var unit = raw.filter { ["id", "version", "schemaVersion", "roleKey", "level", "title", "summary", "scene", "estimatedMinutes", "goalIds"].contains($0.key) }
            unit["questions"] = [visible]; unit["beats"] = []
            let app = XCUIApplication()
            app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
                "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
                "UI_TEST_LEARNING_LOCAL_MEDIA": "1", "UI_TEST_LEARNING_MEDIA_DIRECTORY": directory.path,
                "UI_TEST_LEARNING_UNIT_JSON": String(decoding: try JSONSerialization.data(withJSONObject: unit), as: UTF8.self),
                "UI_TEST_LEARNING_QUESTION_ID": "q1"]
            if large {
                app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
                app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
            }
            app.launch()
            XCTAssertTrue(app.buttons["退出挑战"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts[secondGrade ? "小学二年级" : "小学一年级"].exists)
            let check = app.buttons["检查"]
            XCTAssertFalse(check.isEnabled)
            let play = app.buttons["learning.audio.play"]
            reveal(play, in: app)
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "播放听力"), object: play)], timeout: 10) == .completed)
            if !large {
                let controls = app.otherElements["learning.audio.controls"]
                XCTAssertTrue(controls.exists)
                XCTAssertLessThanOrEqual(controls.frame.height, 64, "普通字号音频区应为紧凑单行")
                XCTAssertGreaterThanOrEqual(play.frame.height, 44, "保留足够的触控高度")
            }
            play.tap()
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "再听一遍"), object: play)], timeout: 10) == .completed)
            for option in ["a", "b", "c"] {
                let button = app.buttons["learning.option.\(option)"]
                reveal(button, in: app)
                XCTAssertTrue(button.isEnabled)
                button.tap()
                XCTAssertTrue(button.isSelected)
                XCTAssertTrue(check.isEnabled)
            }
            XCTAssertFalse(app.buttons["重新载入"].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = id + (large ? "-大字深色" : "-常规")
            attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }

    /// 复用已登记的三段真实音频检查新控件；这份工程组合不进入教学题库。
    func testIndependentAudioOptions() throws {
        continueAfterFailure = false
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appending(path: "Backend/config/learning")
        let ids = ["oliver.primary2.playtime-can", "ruby.primary2.weather-window", "marcus.primary2.photo-time"]
        var unit: [String: Any] = [:]
        var options: [[String: Any]] = []
        var transcripts: [String] = []
        for (index, id) in ids.enumerated() {
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "units/\(id).json"))) as? [String: Any])
            if index == 0 { unit = raw.filter { ["id", "version", "schemaVersion", "roleKey", "level", "title", "summary", "scene", "estimatedMinutes", "goalIds"].contains($0.key) } }
            let questions = try XCTUnwrap(raw["questions"] as? [[String: Any]])
            let audio = try XCTUnwrap(questions.first?["audio"] as? [String: String])
            transcripts.append(try XCTUnwrap(audio["text"]))
            options.append(["id": "sound\(index)", "audio": ["assetId": try XCTUnwrap(audio["assetId"])]])
        }
        unit["questions"] = [["id": "audio-choice-engineering", "type": "audioChoice", "goalId": "preview.goal", "instruction": "选一段声音", "prompt": "声音选项交互预览", "hint": "工程检查，不计入学习记录。", "audioOptions": options]]
        unit["beats"] = []
        for large in [false, true] {
            let app = XCUIApplication()
            app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
                "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
                "UI_TEST_LEARNING_LOCAL_MEDIA": "1", "UI_TEST_LEARNING_MEDIA_DIRECTORY": directory.path,
                "UI_TEST_LEARNING_UNIT_JSON": String(decoding: try JSONSerialization.data(withJSONObject: unit), as: UTF8.self),
                "UI_TEST_LEARNING_QUESTION_ID": "audio-choice-engineering"]
            if large {
                app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
                app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
            }
            app.launch()
            let check = app.buttons["检查"]
            XCTAssertTrue(check.waitForExistence(timeout: 15)); XCTAssertFalse(check.isEnabled)
            for transcript in transcripts { XCTAssertFalse(app.staticTexts[transcript].exists) }
            for index in 0..<3 {
                let play = app.buttons["learning.sound.play.sound\(index)"]
                let select = app.buttons["learning.sound.select.sound\(index)"]
                reveal(play, in: app)
                XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: play)], timeout: 10) == .completed)
                XCTAssertGreaterThanOrEqual(play.frame.height, 44)
                play.tap()
                XCTAssertFalse(select.isSelected, "播放不能替用户选答案")
                XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已听完"), object: play)], timeout: 20) == .completed)
                XCTAssertFalse(check.isEnabled, "听完不代替选择")
            }
            let selection = app.buttons["learning.sound.select.sound2"]
            reveal(selection, in: app); selection.tap()
            XCTAssertTrue(selection.isSelected); XCTAssertTrue(check.isEnabled)
            let slow = app.buttons["learning.sound.slow.sound2"]
            reveal(slow, in: app); slow.tap()
            XCTAssertTrue(app.buttons["停止声音 3"].waitForExistence(timeout: 5))
            app.buttons["learning.sound.play.sound2"].tap()
            XCTAssertTrue(selection.isSelected); XCTAssertTrue(check.isEnabled)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = large ? "声音选项-大字深色" : "声音选项-常规"
            attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }
    /// 仅验证配对交互，复用正式媒体的工程夹具不进入题库。
    func testAudioImageMatching() throws {
        continueAfterFailure = false
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Backend/config/learning")
        func read(_ id: String) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "units/\(id).json"))) as? [String: Any])
        }
        let raw = try read("oliver.primary1.bookmark-colours")
        let original = try XCTUnwrap(raw["questions"] as? [[String: Any]])
        let pictures = try XCTUnwrap(original.first?["options"] as? [[String: Any]])
        var sounds: [[String: Any]] = []
        for (index, id) in ["oliver.primary2.playtime-can", "ruby.primary2.weather-window"].enumerated() {
            let source = try read(id)
            let questions = try XCTUnwrap(source["questions"] as? [[String: Any]])
            let audio = try XCTUnwrap(questions.first?["audio"] as? [String: String])
            sounds.append(["id": "sound\(index)", "audio": ["assetId": try XCTUnwrap(audio["assetId"])]])
        }
        var unit = raw.filter { ["id", "version", "schemaVersion", "roleKey", "level", "title", "summary", "scene", "estimatedMinutes", "goalIds"].contains($0.key) }
        unit["questions"] = [["id": "audio-matching-engineering", "type": "audioMatching", "goalId": "preview.goal", "instruction": "给声音配图", "prompt": "声音与图片", "hint": "工程预览", "audioOptions": sounds, "right": pictures]]
        unit["beats"] = []
        for large in [false, true] {
            let app = XCUIApplication()
            app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
                "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
                "UI_TEST_LEARNING_LOCAL_MEDIA": "1", "UI_TEST_LEARNING_MEDIA_DIRECTORY": directory.path,
                "UI_TEST_LEARNING_UNIT_JSON": String(decoding: try JSONSerialization.data(withJSONObject: unit), as: UTF8.self),
                "UI_TEST_LEARNING_QUESTION_ID": "audio-matching-engineering"]
            if large {
                app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
                app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
            }
            app.launch()
            let check = app.buttons["检查"]
            XCTAssertTrue(check.waitForExistence(timeout: 15))
            for index in 0..<2 {
                let play = app.buttons["learning.sound.play.sound\(index)"]
                reveal(play, in: app)
                XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: play)], timeout: 10) == .completed)
                play.tap()
                XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已听完"), object: play)], timeout: 20) == .completed)
            }
            XCTAssertFalse(check.isEnabled)
            let first = app.buttons["learning.sound.image.a"]
            reveal(first, in: app); first.tap()
            XCTAssertFalse(check.isEnabled, "不能自动补全另一声音")
            let secondSound = app.buttons["learning.sound.select.sound1"]
            reveal(secondSound, in: app); secondSound.tap()
            reveal(first, in: app); first.tap()
            XCTAssertEqual(first.value as? String, "已与声音 2 配对")
            XCTAssertFalse(check.isEnabled, "移用图片必须清除旧配对")
            let firstSound = app.buttons["learning.sound.select.sound0"]
            reveal(firstSound, in: app); firstSound.tap()
            let second = app.buttons["learning.sound.image.b"]
            reveal(second, in: app); second.tap()
            XCTAssertTrue(check.isEnabled)
            let undo = app.buttons["learning.sound.match.undo"]
            reveal(undo, in: app); undo.tap()
            XCTAssertFalse(check.isEnabled)
            reveal(second, in: app); second.tap()
            XCTAssertTrue(check.isEnabled)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "声音配图" + (large ? "-大字深色" : "-常规")
            attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
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
        XCTAssertTrue(element.isHittable, "应能滚动到完整控件：\(element.label)")
    }
}
