import XCTest

@MainActor
final class ChallengeLayoutUITests: XCTestCase {
    /// 使用正式高三公开题面，检查长句配对与重分配，不向后端提交答案。
    func testLongMatchingUsesFullWidthAndAllowsReassignment() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "learning-senior3-preview", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
            "UI_TEST_LEARNING_UNIT_JSON": String(decoding: data, as: UTF8.self),
            "UI_TEST_LEARNING_QUESTION_ID": "s3.astra.r07"]
        addTeardownBlock { app.terminate() }
        for largeText in [false, true] {
            app.launchArguments = largeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []
            app.launch()
            let check = app.buttons["检查"]
            XCTAssertTrue(check.waitForExistence(timeout: 15))
            XCTAssertFalse(check.isEnabled)
            func reveal(_ element: XCUIElement) {
                for _ in 0..<16 {
                    let top = app.buttons["退出挑战"].frame.maxY
                    let bottom = check.frame.minY
                    if element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
                    if element.frame.midY < top { app.swipeDown() } else { app.swipeUp() }
                }
                XCTFail("目标控件无法滚动到可操作区域")
            }
            func pair(_ left: String, _ right: String) {
                let item = app.buttons["learning.matching.item.\(left)"]
                reveal(item); item.tap()
                let choice = app.buttons["learning.matching.option.\(right)"]
                reveal(choice)
                // 点已滚入可见区域的中心，避免XCTest对超高按钮再次自动滚动。
                choice.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let ordinal = left == "l1" ? 1 : left == "l2" ? 2 : 3
                XCTAssertEqual(choice.value as? String, "已与第 \(ordinal) 项配对")
            }
            let current = app.staticTexts["learning.matching.current"]
            reveal(current)
            XCTAssertGreaterThan(current.frame.width, app.frame.width * 0.7)
            pair("l1", "r3")
            XCTAssertFalse(check.isEnabled)
            pair("l2", "r1")
            pair("l3", "r2")
            XCTAssertTrue(check.isEnabled)
            // 同一选项分配给另一项目时，原项目恢复未配对，不能提前提交。
            pair("l3", "r3")
            XCTAssertFalse(check.isEnabled)
            XCTAssertEqual(app.buttons["learning.matching.item.l1"].value as? String, "未配对")
            pair("l1", "r2")
            XCTAssertTrue(check.isEnabled)
            XCTAssertEqual(app.buttons["learning.matching.option.r2"].value as? String, "已与第 1 项配对")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = largeText ? "长句配对最大辅助字号" : "长句配对完整行宽"
            attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }
    /// 正式四级公开快照：长故事滚到底后，新一段必须从头可读。
    func testLongOpeningStoryResetsScrollAndOffersCompactHint() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "learning-cet4-preview", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let unit = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let beats = try XCTUnwrap(unit["beats"] as? [[String: Any]])
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
            "UI_TEST_LEARNING_UNIT_JSON": String(decoding: data, as: UTF8.self), "UI_TEST_LEARNING_STORY": "1"]
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.buttons["开始故事"].waitForExistence(timeout: 15))
        app.buttons["开始故事"].tap()
        for (index, beat) in beats.enumerated() {
            let passage = app.staticTexts.matching(NSPredicate(format: "label == %@", try XCTUnwrap(beat["text"] as? String))).firstMatch
            XCTAssertTrue(passage.waitForExistence(timeout: 5))
            let top = app.buttons["退出挑战"].frame.maxY
            XCTAssertGreaterThan(passage.frame.minY, top, "第\(index + 1)段必须从头显示")
            XCTAssertLessThan(passage.frame.minY, app.frame.midY, "不能沿用上一段末尾偏移")
            let translate = app.buttons["查看中文"]
            for _ in 0..<12 {
                if translate.isHittable && translate.frame.midY < app.buttons[index == beats.count - 1 ? "开始答题" : "继续故事"].frame.minY { break }
                app.swipeUp()
            }
            translate.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", try XCTUnwrap(beat["translation"] as? String))).firstMatch.exists)
            app.buttons[index == beats.count - 1 ? "开始答题" : "继续故事"].tap()
        }
        XCTAssertTrue(app.buttons["检查"].exists)
        let hint = app.buttons["learning.hint"]
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: hint)], timeout: 5) == .completed)
        hint.tap()
        XCTAssertTrue(app.staticTexts["learning.hint.text"].exists)
        XCTAssertEqual(hint.label, "收起提示")
        hint.tap()
        XCTAssertFalse(app.staticTexts["learning.hint.text"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "四级三段完整开场与长题滚动"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testAudioArrangeSupportsReplayAndRemovingSelectedCard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge", "UI_TEST_LEARNING_QUESTION": "audioArrange"]
        app.launch()
        let play = app.buttons["learning.audio.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["按听到的顺序放入卡片"].exists)
        app.buttons["I"].tap()
        XCTAssertFalse(app.buttons["检查"].isEnabled)
        play.tap()
        XCTAssertTrue(app.buttons["再听一遍"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["检查"].isEnabled)
        app.buttons["第 1 项，I"].tap()
        XCTAssertFalse(app.buttons["检查"].isEnabled)
        XCTAssertTrue(app.buttons["I"].isHittable)
        app.buttons["would"].tap()
        app.buttons["I"].tap()
        XCTAssertTrue(app.buttons["第 1 项，would"].exists)
        XCTAssertTrue(app.buttons["第 2 项，I"].exists)
        app.buttons["learning.audio.slow"].tap()
        XCTAssertTrue(app.buttons["停止播放"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "听后排序卡片与紧凑播放器"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testOpeningStoryFinishesBeforeQuestions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "unit-challenge"
        app.launchEnvironment["UI_TEST_LEARNING_STORY"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["开始故事"].waitForExistence(timeout: 15))
        app.buttons["开始故事"].tap()
        XCTAssertTrue(app.staticTexts["工程界面预览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A book falls open. A blue bookmark is inside."].exists)
        app.buttons["查看中文"].tap()
        XCTAssertTrue(app.staticTexts["一本书翻开了，里面夹着一枚蓝色书签。"].exists)
        app.buttons["继续故事"].tap()
        XCTAssertTrue(app.staticTexts["Here it is! Thank you."].exists)
        XCTAssertFalse(app.buttons["检查"].exists)
        XCTAssertFalse(app.buttons["直接开始题目"].exists, "末段仅保留一个开始入口")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "前置故事末段"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["开始答题"].tap()
        XCTAssertTrue(app.buttons["检查"].exists)
        XCTAssertFalse(app.staticTexts["工程界面预览"].exists)
    }
    func testClozeSelectReplaceUndoAndLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for large in [false, true] {
            app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
                "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge", "UI_TEST_LEARNING_QUESTION": "cloze"]
            app.launchArguments = large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []
            if large { app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark" }
            app.launch()
            XCTAssertTrue(app.buttons["退出挑战"].waitForExistence(timeout: 15))
            let initialTree = XCTAttachment(string: app.debugDescription)
            initialTree.name = "多空题初始可访问性树"; initialTree.lifetime = .keepAlways; add(initialTree)
            let check = app.buttons["检查"]
            let first = app.buttons["learning.cloze.slot.first"]
            let second = app.buttons["learning.cloze.slot.second"]
            let one = app.buttons["learning.cloze.token.a"]
            let two = app.buttons["learning.cloze.token.b"]
            let three = app.buttons["learning.cloze.token.c"]
            func tap(_ element: XCUIElement) {
                for _ in 0..<12 {
                    let top = app.buttons["退出挑战"].frame.maxY + 10
                    let bottom = check.frame.minY - 10
                    if element.isHittable, element.frame.midY > top, element.frame.midY < bottom { break }
                    let downward = element.exists && element.frame.midY < top
                    let origin = app.coordinate(withNormalizedOffset: .zero)
                    origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (bottom - top) * (downward ? 0.25 : 0.75)))
                        .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: top + (bottom - top) * (downward ? 0.75 : 0.25))))
                }
                XCTAssertTrue(element.isHittable)
                XCTAssertGreaterThanOrEqual(element.frame.height, 44)
                element.tap()
            }
            XCTAssertFalse(check.isEnabled)
            tap(one)
            XCTAssertEqual(first.value as? String, "one")
            XCTAssertTrue(second.isSelected)
            XCTAssertFalse(check.isEnabled)
            tap(first); tap(three)
            XCTAssertEqual(first.value as? String, "three")
            XCTAssertTrue(one.isEnabled)
            tap(two)
            XCTAssertTrue(check.isEnabled)
            tap(first); tap(app.buttons["learning.cloze.undo"])
            XCTAssertFalse(check.isEnabled)
            XCTAssertEqual(first.value as? String, "未填写")
            tap(one)
            XCTAssertTrue(check.isEnabled)
            XCTAssertEqual(second.value as? String, "two")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = large ? "共享词库-最大字号深色" : "共享词库-替换与撤回"
            attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }

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
        XCTAssertTrue(app.staticTexts["播放已中断，轻点重听。"].waitForExistence(timeout: 5))
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
