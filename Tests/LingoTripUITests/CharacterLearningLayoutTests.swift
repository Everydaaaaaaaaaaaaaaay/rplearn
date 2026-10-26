import XCTest

@MainActor
final class CharacterLearningLayoutTests: XCTestCase {
    func testPendingFilterAndJourneyEntry() {
        let app = launch(state: "active")
        let ongoing = app.buttons["learning.history.20000000-0000-4000-8000-000000000001"]
        let retry = app.buttons["learning.history.20000000-0000-4000-8000-000000000002"]
        let complete = app.buttons["learning.history.20000000-0000-4000-8000-000000000003"]
        XCTAssertTrue(app.buttons["learning.journey"].waitForExistence(timeout: 10))
        reveal(ongoing, in: app)
        XCTAssertTrue(ongoing.label.contains("获得 2 积分"))
        reveal(retry, in: app)
        XCTAssertTrue(retry.label.contains("获得 3 积分"))
        reveal(complete, in: app)
        XCTAssertTrue(complete.label.contains("获得 0 积分"))
        capture(app, name: "记录答对比例三色与实际积分")
        app.swipeDown()
        XCTAssertTrue(app.buttons["learning.start"].label.contains("继续挑战"))
        let filter = app.buttons["learning.history.filter"]
        reveal(filter, in: app)
        XCTAssertEqual(filter.value as? String, "未筛选")
        filter.tap()
        capture(app, name: "挑战记录筛选菜单")
        app.buttons["待补答"].tap()
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(ongoing.exists)
        XCTAssertFalse(complete.exists)
        capture(app, name: "待补答筛选")
        XCTAssertEqual(filter.value as? String, "待补答")
        filter.tap()
        app.buttons["黄色 · 答对 50%–不足70%"].tap()
        XCTAssertEqual(filter.value as? String, "待补答 · 50%–<70%")
        XCTAssertTrue(retry.exists)
        capture(app, name: "待补答与正确率组合筛选")
        filter.tap()
        app.buttons["清除筛选"].tap()
        XCTAssertEqual(filter.value as? String, "未筛选")
        for (label, expected, absent, summary) in [
            ("红色 · 答对 <50%", ongoing, retry, "<50%"),
            ("黄色 · 答对 50%–不足70%", retry, complete, "50%–<70%"),
            ("绿色 · 答对 ≥70%", complete, ongoing, "≥70%")
        ] {
            reveal(filter, in: app)
            filter.tap()
            app.buttons[label].tap()
            XCTAssertEqual(filter.value as? String, summary)
            XCTAssertTrue(expected.exists)
            XCTAssertFalse(absent.exists)
            capture(app, name: "正确率筛选 \(summary)")
        }
        filter.tap()
        app.buttons["待补答"].tap()
        XCTAssertTrue(app.staticTexts["暂无符合筛选的记录"].exists)
        filter.tap()
        app.buttons["清除筛选"].tap()
        reveal(complete, in: app)
        XCTAssertTrue(complete.exists)
        let journey = app.buttons["learning.journey"]
        reveal(journey, in: app)
        journey.tap()
        XCTAssertTrue(app.navigationBars["学习进度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0/60 点"].exists)
        app.buttons["关闭学习进度"].tap()
        XCTAssertTrue(app.buttons["learning.journey"].waitForExistence(timeout: 5))
    }

    func testLargeTextDarkHistoryRemainsReadable() {
        let app = launch(state: "ready", large: true)
        let start = app.buttons["learning.start"]
        XCTAssertTrue(app.buttons["learning.journey"].waitForExistence(timeout: 10))
        reveal(start, in: app)
        XCTAssertTrue(start.label.contains("开启单元挑战"))
        let card = app.otherElements["learning.challenge.card"]
        XCTAssertTrue(card.exists)
        XCTAssertTrue(card.frame.contains(app.buttons["learning.journey"].frame))
        XCTAssertTrue(card.frame.contains(start.frame))
        capture(app, name: "最大字号深色挑战进度")
        let row = app.buttons["learning.history.20000000-0000-4000-8000-000000000002"]
        reveal(row, in: app)
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("周末集市询价与比较商品"))
        XCTAssertTrue(row.label.contains("补答 2 题"))
        XCTAssertTrue(row.label.contains("获得 3 积分"))
        XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
        capture(app, name: "最大字号深色长标题与补答")
    }

    func testReadyCardCombinesLevelStarsAndChallenge() {
        let app = launch(state: "ready")
        let start = app.buttons["learning.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(start.label, "开启单元挑战")
        let card = app.otherElements["learning.challenge.card"]
        XCTAssertTrue(card.exists)
        XCTAssertTrue(card.frame.contains(app.buttons["learning.journey"].frame))
        XCTAssertTrue(card.frame.contains(start.frame))
        XCTAssertFalse(app.staticTexts["单元挑战"].exists)
        XCTAssertFalse(app.buttons["learning.direction"].exists)
        XCTAssertTrue(app.staticTexts["单元练习已解锁"].exists)
        XCTAssertEqual(app.otherElements["learning.unlock.progress"].value as? String, "100% 聊天进度")
        capture(app, name: "档位星级与开启挑战合为一卡")
    }

    func testLockedPracticeShowsUnlockProgressWithoutDirectionRow() {
        let app = launch(state: "empty")
        let progress = app.otherElements["learning.unlock.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(progress.value as? String, "72% 聊天进度")
        XCTAssertTrue(app.staticTexts["单元练习尚未解锁"].exists)
        XCTAssertFalse(app.staticTexts["单元挑战"].exists)
        XCTAssertFalse(app.buttons["learning.direction"].exists)
        XCTAssertFalse(app.buttons["learning.start"].exists)
        capture(app, name: "未解锁练习进度")
    }

    func testLearningCityBackgroundsKeepControlsUsable() {
        let cities = ["london", "melbourne", "newyork", "capetown", "singapore",
                      "dublin", "edinburgh", "vancouver", "auckland", "nairobi",
                      "toronto", "sydney", "neworleans", "manchester", "kingston"]
        for city in cities {
            let app = launch(state: "ready", city: city)
            XCTAssertTrue(app.buttons["learning.start"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.otherElements["learning.unlock.progress"].value as? String, "100% 聊天进度")
            capture(app, name: "learning-city-\(city)")
            let filter = app.buttons["learning.history.filter"]
            reveal(filter, in: app)
            filter.tap()
            XCTAssertTrue(app.buttons["绿色 · 答对 ≥70%"].waitForExistence(timeout: 3))
            app.buttons["绿色 · 答对 ≥70%"].tap()
            XCTAssertEqual(filter.value as? String, "≥70%")
            app.terminate()
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let banner = app.staticTexts["界面预览 · 示例进度，不计入账号"]
        let top = max(app.navigationBars.firstMatch.frame.maxY, banner.exists ? banner.frame.maxY : 0) + 8
        let bottom = app.frame.maxY - 20
        for _ in 0..<14 {
            if element.exists {
                let frame = element.frame
                if element.isHittable && (frame.height > bottom - top || (frame.minY >= top && frame.maxY <= bottom)) { return }
                if frame.minY < top { app.swipeDown() }
                else { app.swipeUp() }
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }

    private func launch(state: String, large: Bool = false, city: String = "london") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "role-learning",
            "UI_TEST_LEARNING_PAGE_STATE": state, "UI_TEST_REGION": city]
        if large {
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launchEnvironment["UI_TEST_CAPTURE_APPEARANCE"] = "dark"
        }
        app.launch()
        addTeardownBlock { app.terminate() }
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
