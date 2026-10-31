import XCTest

@MainActor
final class TabSceneTransitionTests: XCTestCase {
    func testRepeatedTabSelectionKeepsNativeSelectionAndSearchWorking() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "messages"
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.textFields["sceneSearch.field"].waitForExistence(timeout: 15))
        for _ in 0..<2 {
            for title in ["联系人", "活动", "我的", "信息"] {
                let tab = app.mainTabButtons[title]
                tab.tap()
                XCTAssertTrue(tab.isSelected, "SwiftUI 与原生标签栏的选中状态必须一致")
            }
            for title in ["信息", "联系人"] {
                app.mainTabButtons[title].tap()
                let field = app.textFields["sceneSearch.field"]
                XCTAssertTrue(field.waitForExistence(timeout: 3))
                field.tap(); field.typeText("Oliver")
                app.buttons["sceneSearch.dismissKeyboard"].tap()
                app.mainTabButtons[title].tap()
                XCTAssertTrue(field.waitForExistence(timeout: 3))
                XCTAssertNotEqual(field.value as? String, "Oliver", "重选标签应恢复根页面的搜索状态")
            }
        }
    }

    func testSceneTabsReturnToRootOnReselectionAndSwitchBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "home"
        app.launch()
        defer { app.terminate() }

        for (title, entry) in [("活动", "剧情，"), ("我的", "设置，AI、语音与偏好")] {
            app.mainTabButtons[title].tap()
            for switchesAway in [false, true] {
                let entrance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", entry)).firstMatch
                XCTAssertTrue(entrance.waitForExistence(timeout: 15))
                entrance.tap()
                let back = app.navigationBars[title == "活动" ? "剧情" : "设置"].buttons.firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5))
                if switchesAway { app.mainTabButtons["联系人"].tap() }
                app.mainTabButtons[title].tap()
                XCTAssertTrue(back.waitForNonExistence(timeout: 5), "点击标签应关闭二级页面")
                XCTAssertTrue(entrance.isHittable, "初始页面入口应恢复可点击")
            }
        }
    }
    func testMePagesUseNativeBackAndEdgeSwipe() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "me"
        app.launch()
        defer { app.terminate() }

        for (prefix, title) in [("个人资料，", "个人资料"), ("会员订阅", "会员订阅"),
                                ("收藏夹，", "收藏夹"), ("设置，", "设置"), ("记忆档案", "记忆档案")] {
            let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 15))
            entry.tap()
            let navigationBar = app.navigationBars[title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            XCTAssertTrue(navigationBar.buttons.firstMatch.isHittable, "应显示原生返回按钮")
            if title == "个人资料" {
                let subscription = app.buttons["profile.subscription"]
                XCTAssertTrue(subscription.waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["AI 积分"].exists)
                subscription.tap()
                let subscriptionBar = app.navigationBars["会员订阅"]
                XCTAssertTrue(subscriptionBar.waitForExistence(timeout: 5))
                subscriptionBar.buttons.firstMatch.tap()
                XCTAssertTrue(navigationBar.waitForExistence(timeout: 5), "订阅返回应保留个人资料层级")
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
            XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 5), "左缘滑动应返回我的页")
            XCTAssertTrue(entry.isHittable)
        }
    }

    func testContactProfileReturnsToRoot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "contacts"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        defer { app.terminate() }

        for switchesAway in [false, true] {
            let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Oliver")).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 15))
            entry.tap()
            let message = app.buttons["发消息"]
            XCTAssertTrue(message.waitForExistence(timeout: 5))
            if switchesAway { app.mainTabButtons["活动"].tap() }
            app.mainTabButtons["联系人"].tap()
            XCTAssertTrue(message.waitForNonExistence(timeout: 5))
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            XCTAssertTrue(entry.isHittable, "点击标签应返回联系人列表")
        }
    }
}
